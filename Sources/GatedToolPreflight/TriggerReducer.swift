import Foundation

/// Strategies that lower how many times an unconditional gate can fire.
/// Arguing with a speed bump is pure waste (skill).
public enum TriggerReducer {
    public enum Advice: Equatable, CustomStringConvertible {
        case extendExistingFile(insteadOfCreating: String, extend: String)
        case collapseBash([String])
        case preferMktemp(over: String)
        case skipReread(String)
        case singlePatch(insteadOfEdits: Int)
        case surfaceEscapeHatch(envVar: String)

        public var description: String {
            switch self {
            case .extendExistingFile(let neu, let old):
                return "Extend \(old) instead of creating \(neu)"
            case .collapseBash(let steps):
                return "Collapse into one Bash call: " + steps.joined(separator: " && ")
            case .preferMktemp(let over):
                return "Use OUT=$(mktemp -d) instead of \(over)"
            case .skipReread(let path):
                return "Do not re-read \(path); the write already confirmed it"
            case .singlePatch(let n):
                return "One patch script instead of \(n) Edit calls"
            case .surfaceEscapeHatch(let v):
                return "Surface the escape hatch \(v) to the user; do not silently absorb the cost"
            }
        }
    }

    /// Heuristic advisor for a planned sequence of tool calls.
    public static func advise(_ calls: [PlannedCall]) -> [Advice] {
        var advice: [Advice] = []
        let writes = calls.filter { TriggerLedger.family(of: $0.tool) == "write" }
        if writes.count > 1, let first = writes.first?.path {
            for w in writes.dropFirst() {
                if let p = w.path { advice.append(.extendExistingFile(insteadOfCreating: p, extend: first)) }
            }
        }
        let bashes = calls.filter { TriggerLedger.family(of: $0.tool) == "bash" }
        if bashes.count > 1 {
            advice.append(.collapseBash(bashes.map(\.summary)))
        }
        for c in bashes where c.summary.contains("rm -rf") {
            advice.append(.preferMktemp(over: c.summary))
        }
        let edits = calls.filter { TriggerLedger.family(of: $0.tool) == "edit" }
        if edits.count > 2 {
            advice.append(.singlePatch(insteadOfEdits: edits.count))
        }
        // Detect write-then-immediate-read of the same path.
        for i in 0..<(calls.count - 1) {
            let a = calls[i], b = calls[i + 1]
            if TriggerLedger.family(of: a.tool) == "write",
               ["read", "read_file"].contains(b.tool.lowercased()),
               let p = a.path, p == b.path {
                advice.append(.skipReread(p))
            }
        }
        if calls.count >= 5 {
            advice.append(.surfaceEscapeHatch(envVar: "ECC_GATEGUARD=off / ECC_DISABLED_HOOKS"))
        }
        return advice
    }

    /// Estimate how many unconditional first-touch gates a plan will trip,
    /// given what has already fired this session.
    public static func estimatedTriggers(_ calls: [PlannedCall], ledger: TriggerLedger) -> Int {
        var seen = ledger
        var n = 0
        for c in calls {
            let fam = TriggerLedger.family(of: c.tool)
            let key = TriggerLedger.Key(family: fam, path: c.path)
            let sessionKey = TriggerLedger.Key(family: fam, path: nil)
            // First bash of session, or first write to a given path.
            let isFirst: Bool
            if fam == "bash" { isFirst = !seen.fired.contains(sessionKey) }
            else if fam == "write" { isFirst = c.path.map { !seen.fired.contains(.init(family: fam, path: $0)) } ?? !seen.fired.contains(sessionKey) }
            else { isFirst = false }
            if isFirst { n += 1 }
            seen.record(c.tool, path: c.path)
            _ = key
        }
        return n
    }
}
