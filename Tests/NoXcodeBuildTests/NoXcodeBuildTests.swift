import XCTest
@testable import NoXcodeBuild
import ToolkitCore

final class InfoPlistTests: XCTestCase {
    func testEssentials() {
        let info = AppInfo(name: "MacPulse", bundleID: "com.example.macpulse",
                           appleEventsUsageDescription: "Control System Events")
        let xml = info.xml()
        XCTAssertTrue(xml.contains("<key>CFBundleExecutable</key>"))
        XCTAssertTrue(xml.contains("<string>MacPulse</string>"))
        XCTAssertTrue(xml.contains("<key>CFBundlePackageType</key>"))
        XCTAssertTrue(xml.contains("<string>APPL</string>"))
        XCTAssertTrue(xml.contains("<key>LSUIElement</key>"))
        XCTAssertTrue(xml.contains("<true/>"))
        XCTAssertTrue(xml.contains("<key>CFBundleIconFile</key>"))
        XCTAssertTrue(xml.contains("<string>AppIcon</string>"))
        XCTAssertTrue(xml.contains("NSAppleEventsUsageDescription"))
        // Deterministic key order
        XCTAssertEqual(xml, info.xml())
    }

    func testDockAppDisablesLSUIElement() {
        let info = AppInfo(name: "Shown", bundleID: "com.example.shown", lsUIElement: false)
        XCTAssertTrue(info.xml().contains("<key>LSUIElement</key>\n\t\t<false/>")
                      || info.xml().contains("<false/>"))
        let v = info.plistValue()
        if case .dict(let d) = v { XCTAssertEqual(d["LSUIElement"], .bool(false)) }
        else { XCTFail() }
    }
}

final class BundleAndBuildPlanTests: XCTestCase {
    func testSourceMustBeMainSwift() {
        XCTAssertThrowsError(try BuildPlan(sourcePath: "/tmp/App.swift",
                                           info: AppInfo(name: "A", bundleID: "com.a.a"),
                                           destinationDir: "/tmp")) { e in
            XCTAssertEqual(e as? BuildPlan.BuildError, .sourceMustBeNamedMainSwift("App.swift"))
        }
    }

    func testPlanSteps() throws {
        let plan = try BuildPlan(sourcePath: "/src/main.swift",
                                 info: AppInfo(name: "MacPulse", bundleID: "com.example.macpulse"),
                                 destinationDir: "/out",
                                 resources: [(source: "/src/icon.png", name: "extra.png")])
        XCTAssertEqual(plan.bundle.executableRelPath, "Contents/MacOS/MacPulse")
        let steps = plan.steps()
        XCTAssertTrue(steps.contains(where: {
            if case .run(let a) = $0 { return a.first == "/usr/bin/swiftc" && a.contains(where: { $0.hasSuffix("main.swift") }) }
            return false
        }))
        XCTAssertTrue(steps.contains(where: {
            if case .writeFile(let p, let c) = $0 {
                return p.hasSuffix("Info.plist") && c.contains("CFBundleIdentifier")
            }
            return false
        }))
        XCTAssertTrue(steps.contains(where: {
            if case .run(let a) = $0 { return a == ["/usr/bin/codesign", "--force", "--deep", "-s", "-", "/out/MacPulse.app"] }
            return false
        }))
        XCTAssertTrue(plan.bundle.requiredPaths.contains("Contents/Resources/extra.png"))
    }

    func testBuildScript() throws {
        let plan = try BuildPlan(sourcePath: "/src/main.swift",
                                 info: AppInfo(name: "MacPulse", bundleID: "com.example.macpulse"),
                                 destinationDir: "/out")
        let sh = plan.renderBuildScript()
        XCTAssertTrue(sh.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(sh.contains("set -euo pipefail"))
        XCTAssertTrue(sh.contains("codesign --force --deep -s -"))
        XCTAssertTrue(sh.contains("CFBundleIdentifier"))
    }

    func testIconsetPlan() {
        let plan = IconsetPlan()
        XCTAssertEqual(plan.entries.count, 10)
        XCTAssertEqual(plan.entries.last?.pixels, 1024)
        let cmds = plan.sipsCommands(sourcePNG: "/a.png", iconsetDir: "/i.iconset")
        XCTAssertEqual(cmds.count, 10)
        XCTAssertEqual(cmds[0][1], "-z")
        XCTAssertTrue(cmds[0].last!.hasSuffix("icon_16x16.png"))
        let ic = plan.iconutilCommand(iconsetDir: "/i.iconset", outputICNS: "/AppIcon.icns")
        XCTAssertEqual(ic[1], "-c")
    }

    func testIterationLoopUsesAbsoluteBinary() throws {
        let plan = try BuildPlan(sourcePath: "/src/main.swift",
                                 info: AppInfo(name: "MacPulse", bundleID: "com.example.macpulse"),
                                 destinationDir: "/out")
        let loop = IterationLoop(plan: plan)
        XCTAssertEqual(loop.pkillCommand(), ["/usr/bin/pkill", "-f", "/out/MacPulse.app/Contents/MacOS/MacPulse"])
        XCTAssertEqual(loop.openCommand(), ["/usr/bin/open", "/out/MacPulse.app"])
    }

    func testGlassRecipeMentionsBehindWindow() {
        XCTAssertTrue(GlassPanelRecipe.glassBackdrop.contains("blendingMode = .behindWindow"))
        XCTAssertTrue(GlassPanelRecipe.handBuiltGlassCues.contains(where: { $0.contains("counter-light") }))
    }
}
