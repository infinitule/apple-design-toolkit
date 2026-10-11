import Foundation
import ToolkitCore

/// Generates the one-shot install and uninstall scripts. Install runs once
/// via `osascript … with administrator privileges` and leaves a root-owned
/// agent that never again needs a password.
public struct Installer {
    public var appName: String
    public var bundleID: String
    public var registry: CommandRegistry
    /// Path of the agent.sh template inside the app bundle (user-writable).
    /// The installer copies it into the root-owned support directory; root
    /// must never execute the bundle copy.
    public var bundledAgentPath: String

    public init(appName: String, bundleID: String, registry: CommandRegistry,
                bundledAgentPath: String) {
        try! Identifier.validatePathComponent(appName, field: "appName")
        try! Identifier.validateReverseDNS(bundleID, field: "bundleID")
        self.appName = appName
        self.bundleID = bundleID
        self.registry = registry
        self.bundledAgentPath = bundledAgentPath
    }

    public var script: AgentScript { AgentScript(appName: appName, registry: registry) }
    public var daemon: LaunchDaemonSpec { .spoolAgent(appName: appName, bundleID: bundleID, script: script) }

    /// Shell body that runs as root. Paths are quoted; nothing here comes
    /// from a request file.
    public func installShellBody() -> String {
        let s = script
        let plist = daemon.installPath
        let tmpPlist = "/tmp/\(daemon.filename)"
        // The plist is written by the installer itself (heredoc), not taken
        // from the user-writable bundle, so a compromised app cannot change
        // ProgramArguments after signing.
        let plistXML = daemon.xml()
        return """
        set -e
        SUPPORT=\(Shell.quote(s.supportDir))
        SPOOL=\(Shell.quote(s.spoolDir))
        AGENT=\(Shell.quote(s.agentPath))
        PLIST=\(Shell.quote(plist))
        SRC=\(Shell.quote(bundledAgentPath))
        mkdir -p "$SUPPORT" "$SPOOL" \(Shell.quote(s.reportsDir))
        # Sticky world-writable spool (mode 1777), like /tmp.
        chmod 1777 "$SPOOL"
        # Copy out of the app bundle into a root-owned path BEFORE any launchd load.
        cp "$SRC" "$AGENT"
        chown root:wheel "$AGENT" "$SUPPORT"
        chmod 755 "$AGENT"
        chmod 755 "$SUPPORT"
        cat > \(Shell.quote(tmpPlist)) <<'ADT_PLIST'
        \(plistXML)ADT_PLIST
        mv \(Shell.quote(tmpPlist)) "$PLIST"
        chown root:wheel "$PLIST"
        chmod 644 "$PLIST"
        launchctl bootout system/\(Shell.quote(daemon.label)) 2>/dev/null || true
        launchctl bootstrap system "$PLIST"
        """
    }

    public func uninstallShellBody(also removeSupport: Bool = true) -> String {
        var body = """
        set -e
        launchctl bootout system/\(Shell.quote(daemon.label)) 2>/dev/null || true
        rm -f \(Shell.quote(daemon.installPath))
        """
        if removeSupport {
            body += "rm -rf \(Shell.quote(script.supportDir))\n"
        }
        return body
    }

    /// argv for the one GUI admin prompt that installs everything.
    public func installArgv(prompt: String? = nil) -> [String] {
        AppleScript.adminShellScriptArgv(installShellBody(),
                                         prompt: prompt ?? "Install \(appName) helper (last password ever)")
    }

    public func uninstallArgv(prompt: String? = nil) -> [String] {
        AppleScript.adminShellScriptArgv(uninstallShellBody(),
                                         prompt: prompt ?? "Remove \(appName) helper")
    }

    /// Detect installed state from the skill: plist exists AND spool is writable.
    public static func isInstalled(plistPath: String, spoolPath: String,
                                   fileExists: (String) -> Bool,
                                   isWritable: (String) -> Bool) -> Bool {
        fileExists(plistPath) && isWritable(spoolPath)
    }
}

/// App-side client: write `req-<id>`, poll `done-<id>`.
public struct SpoolClient {
    public var spoolDir: String
    public var pollInterval: TimeInterval
    public var timeout: TimeInterval
    public var sleep: (TimeInterval) -> Void
    public var now: () -> Date
    public var write: (String, String) throws -> Void
    public var read: (String) throws -> String?
    public var uuid: () -> String

    public enum ClientError: Error, Equatable {
        case timeout(id: String)
        case rejected(String)
    }

    public init(spoolDir: String, pollInterval: TimeInterval = 0.4, timeout: TimeInterval = 30,
                sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                now: @escaping () -> Date = Date.init,
                write: @escaping (String, String) throws -> Void = {
                    try $1.write(toFile: $0, atomically: true, encoding: .utf8)
                },
                read: @escaping (String) throws -> String? = {
                    FileManager.default.fileExists(atPath: $0)
                        ? try String(contentsOfFile: $0, encoding: .utf8) : nil
                },
                uuid: @escaping () -> String = { UUID().uuidString }) {
        self.spoolDir = spoolDir
        self.pollInterval = pollInterval
        self.timeout = timeout
        self.sleep = sleep
        self.now = now
        self.write = write
        self.read = read
        self.uuid = uuid
    }

    public func submit(_ verb: String) throws -> Reply {
        let clean = Request.sanitizeVerb(verb)
        precondition(clean == verb && !verb.isEmpty, "verb must be lowercase letters only")
        guard let id = Request.sanitizeID(uuid()) else { throw ClientError.rejected("empty id") }
        let reqPath = (spoolDir as NSString).appendingPathComponent("req-\(id)")
        let donePath = (spoolDir as NSString).appendingPathComponent("done-\(id)")
        try write(reqPath, verb + "\n")
        let deadline = now().addingTimeInterval(timeout)
        while now() < deadline {
            if let body = try read(donePath) {
                return try Reply.parse(filename: "done-\(id)", contents: body)
            }
            sleep(pollInterval)
        }
        throw ClientError.timeout(id: id)
    }
}
