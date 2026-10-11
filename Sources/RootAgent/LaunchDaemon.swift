import Foundation
import ToolkitCore

/// LaunchDaemon plist for the spool agent (`WatchPaths` + `RunAtLoad`) and
/// the optional companion telemetry daemon (`StartInterval`).
public struct LaunchDaemonSpec: Equatable {
    public enum Trigger: Equatable {
        case watchPaths([String])
        case startInterval(Int)
    }

    public var label: String
    public var programArguments: [String]
    public var trigger: Trigger
    public var runAtLoad: Bool
    public var workingDirectory: String?
    public var standardOut: String?
    public var standardError: String?
    public var processType: String?

    public init(label: String, programArguments: [String], trigger: Trigger,
                runAtLoad: Bool = true, workingDirectory: String? = nil,
                standardOut: String? = nil, standardError: String? = nil,
                processType: String? = "Background") {
        try! Identifier.validateReverseDNS(label, field: "label")
        precondition(!programArguments.isEmpty)
        self.label = label
        self.programArguments = programArguments
        self.trigger = trigger
        self.runAtLoad = runAtLoad
        self.workingDirectory = workingDirectory
        self.standardOut = standardOut
        self.standardError = standardError
        self.processType = processType
    }

    public var filename: String { label + ".plist" }
    public var installPath: String { "/Library/LaunchDaemons/\(filename)" }

    public func plistValue() -> PlistValue {
        var dict: [String: PlistValue] = [
            "Label": .string(label),
            "ProgramArguments": .array(programArguments.map(PlistValue.string)),
            "RunAtLoad": .bool(runAtLoad),
        ]
        switch trigger {
        case .watchPaths(let paths):
            dict["WatchPaths"] = .array(paths.map(PlistValue.string))
        case .startInterval(let secs):
            dict["StartInterval"] = .integer(secs)
        }
        if let workingDirectory { dict["WorkingDirectory"] = .string(workingDirectory) }
        if let standardOut { dict["StandardOutPath"] = .string(standardOut) }
        if let standardError { dict["StandardErrorPath"] = .string(standardError) }
        if let processType { dict["ProcessType"] = .string(processType) }
        return .dict(dict)
    }

    public func xml() -> String { PlistWriter.xml(plistValue()) }

    /// Spool-watching agent daemon matching the skill.
    public static func spoolAgent(appName: String, bundleID: String, script: AgentScript) -> LaunchDaemonSpec {
        try! Identifier.validateReverseDNS(bundleID, field: "bundleID")
        return LaunchDaemonSpec(
            label: bundleID + ".agent",
            programArguments: ["/bin/bash", script.agentPath],
            trigger: .watchPaths([script.spoolDir]),
            runAtLoad: true,
            workingDirectory: script.supportDir,
            standardOut: "/var/log/\(script.logTag)-agent.out",
            standardError: "/var/log/\(script.logTag)-agent.err")
    }

    /// Companion telemetry governor (StartInterval=60).
    public static func telemetryGovernor(appName: String, bundleID: String,
                                         programArguments: [String],
                                         interval: Int = 60) -> LaunchDaemonSpec {
        try! Identifier.validateReverseDNS(bundleID, field: "bundleID")
        try! Identifier.validatePathComponent(appName, field: "appName")
        return LaunchDaemonSpec(
            label: bundleID + ".governor",
            programArguments: programArguments,
            trigger: .startInterval(interval),
            runAtLoad: true)
    }
}
