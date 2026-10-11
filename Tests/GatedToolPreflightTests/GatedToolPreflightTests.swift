import XCTest
@testable import GatedToolPreflight

final class GateClassifierTests: XCTestCase {
    func testContentCheckingFromHints() {
        var c = GateClassifier()
        let d = Denial(tool: "Write", path: "a.swift",
                       message: "Please declare callers, rollback, and data before writing.")
        let diag = c.diagnose(denial: d, retrySucceededWithIdenticalInput: false,
                              deniedAgainOnDifferentFirstTouchDespitePreamble: false)
        guard case .contentChecking(let hints) = diag else { return XCTFail("\(diag)") }
        XCTAssertTrue(hints.contains("callers"))
        XCTAssertTrue(hints.contains("rollback"))
        XCTAssertTrue(hints.contains("data"))
    }

    func testUnconditionalFromIdenticalRetry() {
        var c = GateClassifier()
        let d = Denial(tool: "Bash", message: "first bash of session")
        let diag = c.diagnose(denial: d, retrySucceededWithIdenticalInput: true,
                              deniedAgainOnDifferentFirstTouchDespitePreamble: nil)
        guard case .unconditional(let key) = diag else { return XCTFail("\(diag)") }
        XCTAssertEqual(key.family, "bash")
    }

    func testUnconditionalFromSecondFirstTouch() {
        var c = GateClassifier()
        let d = Denial(tool: "Write", path: "b.swift", message: "blocked")
        let diag = c.diagnose(denial: d, retrySucceededWithIdenticalInput: nil,
                              deniedAgainOnDifferentFirstTouchDespitePreamble: true)
        guard case .unconditional = diag else { return XCTFail("\(diag)") }
    }

    func testLedgerScope() {
        var ledger = TriggerLedger()
        ledger.record("Write", path: "a.swift")
        XCTAssertTrue(ledger.hasFired("Write", path: "a.swift"))
        XCTAssertFalse(ledger.hasFired("Write", path: "b.swift"))
        XCTAssertEqual(TriggerLedger.family(of: "run_terminal_cmd"), "bash")
        XCTAssertEqual(TriggerLedger.family(of: "StrReplace"), "edit")
    }
}

final class PreambleAndReducerTests: XCTestCase {
    func testBatchPreamble() {
        let calls = [
            PlannedCall(tool: "Write", path: "a.swift", summary: "create a",
                        declaration: Declaration(callers: "none", noDuplicate: "checked",
                                                 data: "Int x", rollback: "git checkout -- a.swift",
                                                 verbatimInstruction: "add a.swift")),
            PlannedCall(tool: "Write", path: "b.swift", summary: "create b",
                        declaration: Declaration(callers: "none", noDuplicate: "checked",
                                                 data: "Int y", rollback: "git checkout -- b.swift",
                                                 verbatimInstruction: "add b.swift")),
        ]
        let batch = PreamblePlanner().plan(calls)
        XCTAssertTrue(batch.preamble.contains("Preflight for 2 gated call(s)"))
        XCTAssertTrue(batch.preamble.contains("a.swift"))
        XCTAssertTrue(batch.preamble.contains("b.swift"))
        XCTAssertTrue(batch.preamble.contains("Rollback: git checkout -- a.swift"))
    }

    func testTriggerReducer() {
        let calls = [
            PlannedCall(tool: "Write", path: "a.swift", summary: "a"),
            PlannedCall(tool: "Write", path: "b.swift", summary: "b"),
            PlannedCall(tool: "Bash", summary: "swift build"),
            PlannedCall(tool: "Bash", summary: "rm -rf /tmp/x && mkdir /tmp/x"),
            PlannedCall(tool: "Edit", path: "a.swift", summary: "e1"),
            PlannedCall(tool: "Edit", path: "a.swift", summary: "e2"),
            PlannedCall(tool: "Edit", path: "a.swift", summary: "e3"),
            PlannedCall(tool: "Write", path: "c.swift", summary: "c"),
            PlannedCall(tool: "Read", path: "c.swift", summary: "re-read"),
        ]
        let advice = TriggerReducer.advise(calls)
        XCTAssertTrue(advice.contains(where: {
            if case .extendExistingFile(let n, _) = $0 { return n == "b.swift" }
            return false
        }))
        XCTAssertTrue(advice.contains(where: { if case .collapseBash = $0 { return true }; return false }))
        XCTAssertTrue(advice.contains(where: { if case .preferMktemp = $0 { return true }; return false }))
        XCTAssertTrue(advice.contains(where: { if case .singlePatch(let n) = $0 { return n == 3 }; return false }))
        XCTAssertTrue(advice.contains(where: { if case .skipReread("c.swift") = $0 { return true }; return false }))
        XCTAssertTrue(advice.contains(where: { if case .surfaceEscapeHatch = $0 { return true }; return false }))
    }

    func testEstimatedTriggers() {
        var ledger = TriggerLedger()
        let calls = [
            PlannedCall(tool: "Bash", summary: "one"),
            PlannedCall(tool: "Bash", summary: "two"),
            PlannedCall(tool: "Write", path: "a.swift", summary: "a"),
            PlannedCall(tool: "Write", path: "a.swift", summary: "a again"),
            PlannedCall(tool: "Write", path: "b.swift", summary: "b"),
        ]
        // Fresh session: first bash + first write a + first write b = 3
        XCTAssertEqual(TriggerReducer.estimatedTriggers(calls, ledger: ledger), 3)
        ledger.record("Bash")
        // Bash already fired: only the two writes
        XCTAssertEqual(TriggerReducer.estimatedTriggers(calls, ledger: ledger), 2)
    }
}
