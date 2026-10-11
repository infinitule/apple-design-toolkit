import Foundation

/// Declaration a content-checking gate wants before a tool call.
public struct Declaration: Equatable {
    public var callers: String
    public var noDuplicate: String
    public var data: String
    public var rollback: String
    public var verbatimInstruction: String

    public init(callers: String, noDuplicate: String, data: String,
                rollback: String, verbatimInstruction: String) {
        self.callers = callers
        self.noDuplicate = noDuplicate
        self.data = data
        self.rollback = rollback
        self.verbatimInstruction = verbatimInstruction
    }

    public func render() -> String {
        """
        Callers: \(callers)
        No duplicate: \(noDuplicate)
        Data: \(data)
        Rollback: \(rollback)
        Verbatim instruction: \(verbatimInstruction)
        """
    }
}

public struct PlannedCall: Equatable {
    public var tool: String
    public var path: String?
    public var summary: String
    public var declaration: Declaration?
    public init(tool: String, path: String? = nil, summary: String, declaration: Declaration? = nil) {
        self.tool = tool; self.path = path; self.summary = summary; self.declaration = declaration
    }
}

/// Batch one preamble across several pending gated calls (skill: "four
/// gated writes coming up → one preamble covering all four").
public struct PreamblePlanner {
    public init() {}

    public struct Batch: Equatable {
        public var preamble: String
        public var calls: [PlannedCall]
    }

    public func plan(_ calls: [PlannedCall]) -> Batch {
        var sections: [String] = []
        for (i, c) in calls.enumerated() {
            var block = "### Call \(i + 1): \(c.tool)"
            if let path = c.path { block += " \(path)" }
            block += "\n\(c.summary)"
            if let d = c.declaration { block += "\n" + d.render() }
            sections.append(block)
        }
        let preamble = sections.isEmpty ? "" :
            "Preflight for \(calls.count) gated call(s):\n\n" + sections.joined(separator: "\n\n")
        return Batch(preamble: preamble, calls: calls)
    }
}
