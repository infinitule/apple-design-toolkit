import Foundation

/// Two kinds of gate from the gated-tool-preflight skill. They need opposite
/// responses; diagnosing which one you face is the whole skill.
public enum GateKind: String, Equatable {
    /// Reads the message and passes once the required declaration is present.
    case contentChecking
    /// Fires on the first occurrence of a trigger regardless of content; a
    /// byte-identical retry succeeds. No preamble can prevent these.
    case unconditional
}

public struct Denial: Equatable {
    public var tool: String
    public var path: String?
    public var message: String
    public var attempt: Int
    public init(tool: String, path: String? = nil, message: String, attempt: Int = 1) {
        self.tool = tool; self.path = path; self.message = message; self.attempt = attempt
    }
}

/// Running ledger of which triggers have fired. Scope is per-path and
/// per-session-per-family, not once-ever (skill).
public struct TriggerLedger: Equatable {
    public struct Key: Hashable {
        public var family: String
        public var path: String?
        public init(family: String, path: String? = nil) {
            self.family = family; self.path = path
        }
    }
    public private(set) var fired: Set<Key> = []
    public init() {}

    public mutating func record(_ tool: String, path: String? = nil) {
        fired.insert(Key(family: Self.family(of: tool), path: path))
        fired.insert(Key(family: Self.family(of: tool), path: nil))
    }

    public func hasFired(_ tool: String, path: String? = nil) -> Bool {
        if let path, fired.contains(Key(family: Self.family(of: tool), path: path)) { return true }
        return fired.contains(Key(family: Self.family(of: tool), path: nil))
            && path == nil
    }

    public static func family(of tool: String) -> String {
        switch tool.lowercased() {
        case "bash", "shell", "run_terminal_cmd": return "bash"
        case "write", "create_file": return "write"
        case "edit", "strreplace", "apply_patch": return "edit"
        default: return tool.lowercased()
        }
    }
}

public struct GateClassifier {
    public var ledger: TriggerLedger
    public init(ledger: TriggerLedger = .init()) { self.ledger = ledger }

    public enum Diagnosis: Equatable {
        case contentChecking(requiredHints: [String])
        case unconditional(trigger: TriggerLedger.Key)
        case unknown
    }

    /// Classify from a denial and what happened on the next attempt.
    /// Protocol from the skill: on denial #1, add the declaration and retry.
    /// If a subsequent *different* first-touch is denied even though you
    /// declared everything up front, it is unconditional.
    public mutating func diagnose(denial: Denial, retrySucceededWithIdenticalInput: Bool?,
                                  deniedAgainOnDifferentFirstTouchDespitePreamble: Bool?) -> Diagnosis {
        ledger.record(denial.tool, path: denial.path)
        if deniedAgainOnDifferentFirstTouchDespitePreamble == true {
            return .unconditional(trigger: .init(family: TriggerLedger.family(of: denial.tool), path: denial.path))
        }
        if retrySucceededWithIdenticalInput == true {
            return .unconditional(trigger: .init(family: TriggerLedger.family(of: denial.tool), path: denial.path))
        }
        let hints = Self.extractHints(from: denial.message)
        if !hints.isEmpty || denial.message.localizedCaseInsensitiveContains("declare")
            || denial.message.localizedCaseInsensitiveContains("justify")
            || denial.message.localizedCaseInsensitiveContains("preamble") {
            return .contentChecking(requiredHints: hints)
        }
        if retrySucceededWithIdenticalInput == false {
            return .contentChecking(requiredHints: hints)
        }
        return .unknown
    }

    static func extractHints(from message: String) -> [String] {
        let keys = ["callers", "rollback", "data", "verbatim", "no duplicate", "instruction"]
        return keys.filter { message.localizedCaseInsensitiveContains($0) }
    }
}
