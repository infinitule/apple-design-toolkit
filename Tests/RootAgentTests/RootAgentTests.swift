import XCTest
@testable import RootAgent
import ToolkitCore

final class RequestParsingTests: XCTestCase {
    func testBareVerb() throws {
        let r = try Request.parse(filename: "req-a1b2", contents: "tune\n")
        XCTAssertEqual(r.id, "a1b2")
        XCTAssertEqual(r.verb, "tune")
    }

    func testStripsEverythingButLowercase() throws {
        // Injection attempt: verb with args, paths, shell metacharacters.
        let r = try Request.parse(filename: "req-x", contents: "tune; rm -rf /; echo $(whoami)\n")
        XCTAssertEqual(r.verb, "tunermrfechowhoami") // only a-z survive, and that is NOT in the whitelist
        XCTAssertNil(CommandRegistry.macPulseDefaults.lookup(r.verb))
    }

    func testSanitizesID() throws {
        let r = try Request.parse(filename: "req-../etc/passwd", contents: "tune")
        XCTAssertEqual(r.id, "etcpasswd")
        XCTAssertNil(Request.sanitizeID("!!!"))
        XCTAssertEqual(Request.sanitizeID("Ok_12"), "Ok12")
    }

    func testRejectsEmptyVerbAfterStrip() {
        XCTAssertThrowsError(try Request.parse(filename: "req-1", contents: "123 !!!\n")) { e in
            XCTAssertEqual(e as? Request.ParseError, .noVerb)
        }
    }

    func testNULTruncation() throws {
        let r = try Request.parse(filename: "req-1", contents: "tune\0deep")
        XCTAssertEqual(r.verb, "tune")
    }

    func testReplyRoundTrip() throws {
        let ok = Reply(id: "abc", kind: .ok)
        XCTAssertEqual(ok.filename, "done-abc")
        XCTAssertEqual(try Reply.parse(filename: ok.filename, contents: ok.contents).kind, .ok)
        let path = Reply(id: "abc", kind: .path("/tmp/x.txt"))
        XCTAssertEqual(try Reply.parse(filename: path.filename, contents: path.contents).kind, .path("/tmp/x.txt"))
    }
}

final class StateMachineTests: XCTestCase {
    var processor: RequestProcessor!
    override func setUp() {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
        processor = RequestProcessor(registry: .macPulseDefaults, now: { fixed }, uuid: { "fixed" })
    }

    func testHappyPathTune() {
        var s = processor.accept(filename: "req-a1", contents: "tune\n")
        guard case .validated(let req, let cmd) = s else { return XCTFail("\(s)") }
        XCTAssertEqual(req.verb, "tune")
        XCTAssertEqual(cmd.executable, "/usr/bin/pmset")
        s = processor.markRunning(s)
        s = processor.finish(s, exitCode: 0, stdout: Data(), stderr: Data())
        guard case .replied(_, let reply) = s else { return XCTFail("\(s)") }
        XCTAssertEqual(reply.kind, .ok)
    }

    func testUnknownVerbRejected() {
        let s = processor.accept(filename: "req-a1", contents: "hack\n")
        guard case .rejected(let req, .unknownVerb(let v)) = s else { return XCTFail("\(s)") }
        XCTAssertEqual(req?.verb, "hack")
        XCTAssertEqual(v, "hack")
    }

    func testReportPathBuiltByAgent() {
        var s = processor.accept(filename: "req-a1", contents: "deep\n")
        s = processor.markRunning(s)
        s = processor.finish(s, exitCode: 0, stdout: Data("sample".utf8), stderr: Data())
        guard case .replied(_, let reply) = s else { return XCTFail("\(s)") }
        guard case .path(let p) = reply.kind else { return XCTFail("\(reply)") }
        XCTAssertTrue(p.hasPrefix("/Library/Application Support/MacPulse/reports/scan-"))
        XCTAssertTrue(p.hasSuffix(".txt"))
        // Timestamp is UTC from the injected clock.
        XCTAssertTrue(p.contains("20231114-221320"))
    }

    func testExecutionFailure() {
        var s = processor.accept(filename: "req-a1", contents: "purge\n")
        s = processor.markRunning(s)
        s = processor.finish(s, exitCode: 1, stdout: Data(), stderr: Data("denied".utf8))
        guard case .rejected(_, .executionFailed(let m)) = s else { return XCTFail("\(s)") }
        XCTAssertEqual(m, "denied")
    }

    func testStaleReplyCleaner() {
        let now = Date(timeIntervalSince1970: 10_000)
        let cleaner = StaleReplyCleaner(maxAge: 300, now: { now })
        let expired = cleaner.expired(entries: [
            (name: "done-old", mtime: now.addingTimeInterval(-301)),
            (name: "done-new", mtime: now.addingTimeInterval(-10)),
            (name: "req-pending", mtime: now.addingTimeInterval(-1000)),
        ])
        XCTAssertEqual(expired, ["done-old"])
    }
}

final class GeneratorTests: XCTestCase {
    func testAgentScriptBakesWhitelist() {
        let script = AgentScript(appName: "MacPulse", registry: .macPulseDefaults).render()
        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(script.contains("tr -cd 'a-z'"))
        XCTAssertTrue(script.contains("id=\"${id//[^a-zA-Z0-9]/}\""))
        XCTAssertTrue(script.contains("tune)"))
        XCTAssertTrue(script.contains("/usr/bin/pmset -a lowpowermode 1"))
        XCTAssertTrue(script.contains("find \"$SPOOL\""))
        // Nothing user-supplied can appear as an argument: no unquoted expansions of verb into argv.
        XCTAssertFalse(script.contains("$verb "))
    }

    func testLaunchDaemonPlist() {
        let script = AgentScript(appName: "MacPulse", registry: .macPulseDefaults)
        let d = LaunchDaemonSpec.spoolAgent(appName: "MacPulse", bundleID: "com.example.macpulse", script: script)
        let xml = d.xml()
        XCTAssertTrue(xml.contains("<key>WatchPaths</key>"))
        XCTAssertTrue(xml.contains(script.spoolDir))
        XCTAssertTrue(xml.contains("<string>/bin/bash</string>"))
        XCTAssertTrue(xml.contains(script.agentPath))
        XCTAssertTrue(xml.contains("<key>RunAtLoad</key>"))
        XCTAssertEqual(d.installPath, "/Library/LaunchDaemons/com.example.macpulse.agent.plist")
    }

    func testInstallerCopiesOutOfBundle() {
        let inst = Installer(appName: "MacPulse", bundleID: "com.example.macpulse",
                             registry: .macPulseDefaults,
                             bundledAgentPath: "/Applications/MacPulse.app/Contents/Resources/agent.sh")
        let body = inst.installShellBody()
        XCTAssertTrue(body.contains("chmod 1777"))
        XCTAssertTrue(body.contains("chown root:wheel"))
        XCTAssertTrue(body.contains("launchctl bootstrap system"))
        XCTAssertTrue(body.contains("cp "))
        // Plist is written via heredoc, not copied from the bundle.
        XCTAssertTrue(body.contains("ADT_PLIST"))
        XCTAssertTrue(Installer.isInstalled(plistPath: "/x", spoolPath: "/y",
                                            fileExists: { $0 == "/x" }, isWritable: { $0 == "/y" }))
        XCTAssertFalse(Installer.isInstalled(plistPath: "/x", spoolPath: "/y",
                                             fileExists: { _ in true }, isWritable: { _ in false }))
    }

    func testSpoolClientPolling() throws {
        var files: [String: String] = [:]
        var ticks = 0
        let client = SpoolClient(
            spoolDir: "/spool", pollInterval: 0.01, timeout: 1,
            sleep: { _ in
                ticks += 1
                // On the second poll, the agent "replies".
                if ticks == 2 { files["/spool/done-FIXED"] = "ok\n" }
            },
            now: {
                // Advance 0.1s per call so we don't trip the timeout.
                Date(timeIntervalSince1970: Double(ticks) * 0.1)
            },
            write: { path, body in files[path] = body },
            read: { files[$0] },
            uuid: { "FIXED" })
        let reply = try client.submit("tune")
        XCTAssertEqual(files["/spool/req-FIXED"], "tune\n")
        XCTAssertEqual(reply.kind, .ok)
        XCTAssertEqual(ticks, 2)
    }
}

final class BatteryTests: XCTestCase {
    func testTwoComplementAmperage() {
        // Small positive.
        XCTAssertEqual(BatteryTelemetry.signedAmperage(1500), 1500)
        // Discharge: raw > Int64.max (ioreg reports InstantAmperage as unsigned).
        let raw: UInt64 = UInt64(bitPattern: Int64(-2500))
        XCTAssertGreaterThan(raw, UInt64(Int64.max))
        XCTAssertEqual(BatteryTelemetry.signedAmperage(raw), -2500)
        XCTAssertEqual(BatteryTelemetry.amperes(fromInstant: raw), -2.5, accuracy: 1e-12)
        // The skill's awk heuristic ("> 9.2e18") sits just below Int64.max so a
        // floating-point comparison can catch the sign bit without UInt64.
        XCTAssertEqual(BatteryTelemetry.unsignedThreshold, 9_200_000_000_000_000_000)
        XCTAssertLessThan(BatteryTelemetry.unsignedThreshold, UInt64(Int64.max))
    }

    func testTopLevelOnlyParsing() {
        let text = """
        +-o AppleSmartBattery  <class AppleSmartBattery>
          {
            "Voltage" = 12000
            "InstantAmperage" = 18446744073709549116
            "CurrentCapacity" = 80
            "Nested" = {"InstantAmperage" = 99999, "Voltage" = 1}
          }
        """
        // 18446744073709549116 == UInt64(bitPattern: -2500)
        let sample = BatteryTelemetry.sample(fromIOReg: text)
        XCTAssertEqual(sample?.volts, 12)
        XCTAssertEqual(sample?.amperes ?? 0, -2.5, accuracy: 1e-9)
        XCTAssertEqual(sample?.percent, 80)
        // Nested InstantAmperage must not win.
        XCTAssertNotEqual(sample?.amperes ?? 0, 99.999, accuracy: 0.1)
    }

    func testKalmanSmoothsAndRoundTrips() {
        var k = Kalman1D(estimate: 0, error: 1, processNoise: 0.05, measurementNoise: 2.0)
        var last = 0.0
        for _ in 0..<40 { last = k.update(10) }
        XCTAssertEqual(last, 10, accuracy: 0.3)
        // A noisy spike should not jump all the way to the measurement.
        let before = k.estimate
        let spiked = k.update(100)
        XCTAssertLessThan(spiked, 100)
        XCTAssertGreaterThan(spiked, before)
        XCTAssertEqual(Kalman1D.deserialize(k.serialize())?.estimate ?? -1, k.estimate, accuracy: 1e-9)
        XCTAssertNil(Kalman1D.deserialize("not a state"))
    }
}
