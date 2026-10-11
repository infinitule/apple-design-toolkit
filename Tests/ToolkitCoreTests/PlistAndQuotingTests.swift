import XCTest
@testable import ToolkitCore

final class PlistWriterTests: XCTestCase {
    func testSortedKeysAndEscaping() {
        let xml = PlistWriter.xml([
            "z": "tail",
            "a": "ampersand & <tag>",
            "flag": true,
            "n": 42,
            "kids": [.string("x"), .integer(1)],
        ])
        XCTAssertTrue(xml.hasPrefix("<?xml version=\"1.0\""))
        XCTAssertTrue(xml.contains("<!DOCTYPE plist PUBLIC"))
        // Keys must appear in alphabetical order: a, flag, kids, n, z
        let a = xml.range(of: "<key>a</key>")!
        let flag = xml.range(of: "<key>flag</key>")!
        let kids = xml.range(of: "<key>kids</key>")!
        let n = xml.range(of: "<key>n</key>")!
        let z = xml.range(of: "<key>z</key>")!
        XCTAssertTrue(a.lowerBound < flag.lowerBound)
        XCTAssertTrue(flag.lowerBound < kids.lowerBound)
        XCTAssertTrue(kids.lowerBound < n.lowerBound)
        XCTAssertTrue(n.lowerBound < z.lowerBound)
        XCTAssertTrue(xml.contains("<string>ampersand &amp; &lt;tag&gt;</string>"))
        XCTAssertTrue(xml.contains("<true/>"))
        XCTAssertTrue(xml.contains("<integer>42</integer>"))
    }

    func testEmptyContainers() {
        let xml = PlistWriter.xml(["emptyArr": .array([]), "emptyDict": .dict([:])])
        XCTAssertTrue(xml.contains("<array/>"))
        XCTAssertTrue(xml.contains("<dict/>"))
    }

    func testRealFormatting() {
        XCTAssertEqual(PlistWriter.formatReal(3.0), "3")
        XCTAssertEqual(PlistWriter.formatReal(3.5), "3.5")
    }

    func testDeterministic() {
        let v: PlistValue = ["b": 1, "a": 2]
        XCTAssertEqual(PlistWriter.xml(v), PlistWriter.xml(v))
    }
}

final class ShellQuotingTests: XCTestCase {
    func testSafeUnquoted() {
        XCTAssertEqual(Shell.quote("hello_world-1.2"), "hello_world-1.2")
    }

    func testSpacesAndQuotes() {
        XCTAssertEqual(Shell.quote("a b"), "'a b'")
        XCTAssertEqual(Shell.quote("it's"), "'it'\\''s'")
    }

    func testJoin() {
        XCTAssertEqual(Shell.join(["/bin/echo", "hi there"]), "/bin/echo 'hi there'")
    }

    func testAppleScriptEscaping() {
        XCTAssertEqual(AppleScript.stringLiteral("say \"hi\"\\"), "\"say \\\"hi\\\"\\\\\"")
        let argv = AppleScript.adminShellScriptArgv("echo ok", prompt: "Install")
        XCTAssertEqual(argv[0], "/usr/bin/osascript")
        XCTAssertTrue(argv[2].contains("with administrator privileges"))
        XCTAssertTrue(argv[2].contains("with prompt \"Install\""))
    }
}

final class IdentifierTests: XCTestCase {
    func testReverseDNS() {
        XCTAssertNoThrow(try Identifier.validateReverseDNS("com.example.app"))
        XCTAssertThrowsError(try Identifier.validateReverseDNS("noperiod"))
        XCTAssertThrowsError(try Identifier.validateReverseDNS("com..example"))
        XCTAssertThrowsError(try Identifier.validateReverseDNS("com.example.app!"))
        XCTAssertThrowsError(try Identifier.validateReverseDNS(""))
    }

    func testPathComponent() {
        XCTAssertNoThrow(try Identifier.validatePathComponent("MacPulse"))
        XCTAssertThrowsError(try Identifier.validatePathComponent(".hidden"))
        XCTAssertThrowsError(try Identifier.validatePathComponent("-rf"))
        XCTAssertThrowsError(try Identifier.validatePathComponent("a/b"))
        XCTAssertThrowsError(try Identifier.validatePathComponent(""))
    }
}
