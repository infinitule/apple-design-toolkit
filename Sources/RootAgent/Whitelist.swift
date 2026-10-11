import Foundation

/// A command the root agent is allowed to run. Arguments are fixed at
/// definition time. Nothing in a request file can change them.
public struct WhitelistedCommand: Equatable {
    public enum Output: Equatable {
        /// Reply with the literal body "ok".
        case ok
        /// Capture stdout into a report file under a root-owned directory and
        /// reply with that absolute path. The filename is built by the agent
        /// (`scan-YYYYMMDD-HHMMSS.txt`); the request never chooses it.
        case report(directory: String, prefix: String)
    }

    public var verb: String
    /// Absolute path of the executable (or a shell path for a fixed pipeline
    /// that starts with `/bin/sh -c` and a constant string).
    public var executable: String
    public var arguments: [String]
    public var output: Output
    public var description: String

    public init(verb: String, executable: String, arguments: [String] = [],
                output: Output = .ok, description: String = "") {
        precondition(Request.sanitizeVerb(verb) == verb && !verb.isEmpty,
                     "verb must be lowercase letters only")
        self.verb = verb
        self.executable = executable
        self.arguments = arguments
        self.output = output
        self.description = description
    }
}

/// Registry of allowed verbs. Lookups are O(1); unknown verbs are rejected
/// without ever constructing a Process.
public struct CommandRegistry: Equatable {
    private var byVerb: [String: WhitelistedCommand]

    public init(_ commands: [WhitelistedCommand] = []) {
        var map: [String: WhitelistedCommand] = [:]
        for c in commands {
            precondition(map[c.verb] == nil, "duplicate verb \(c.verb)")
            map[c.verb] = c
        }
        self.byVerb = map
    }

    public var verbs: Set<String> { Set(byVerb.keys) }
    public var commands: [WhitelistedCommand] { byVerb.values.sorted { $0.verb < $1.verb } }

    public func lookup(_ verb: String) -> WhitelistedCommand? { byVerb[verb] }

    /// The MacPulse-style starter set from the skill. Every executable is an
    /// absolute path; every argument is a constant.
    public static let macPulseDefaults = CommandRegistry([
        WhitelistedCommand(
            verb: "tune",
            executable: "/usr/bin/pmset",
            arguments: ["-a", "lowpowermode", "1"],
            output: .ok,
            description: "Enable low-power mode system-wide"),
        WhitelistedCommand(
            verb: "untune",
            executable: "/usr/bin/pmset",
            arguments: ["-a", "lowpowermode", "0"],
            output: .ok,
            description: "Disable low-power mode"),
        WhitelistedCommand(
            verb: "purge",
            executable: "/usr/sbin/purge",
            arguments: [],
            output: .ok,
            description: "Purge disk cache"),
        WhitelistedCommand(
            verb: "deep",
            executable: "/usr/bin/powermetrics",
            arguments: ["--samplers", "cpu_power,gpu_power", "-i", "1000", "-n", "5"],
            output: .report(directory: "/Library/Application Support/MacPulse/reports", prefix: "scan"),
            description: "Five-second power sample written to a root-owned report"),
    ])
}
