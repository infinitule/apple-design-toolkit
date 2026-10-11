import Foundation
import RootAgent
import ToolkitCore

@main
enum ADTRootAgent {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else { printUsage(); exit(2) }
        var app = "MacPulse"
        var id = "com.example.macpulse"
        var out: String?
        var rest = Array(args.dropFirst())
        var i = 0
        var filtered: [String] = []
        while i < rest.count {
            switch rest[i] {
            case "--name": i += 1; app = rest[i]
            case "--id": i += 1; id = rest[i]
            case "-o": i += 1; out = rest[i]
            default: filtered.append(rest[i])
            }
            i += 1
        }
        let registry = CommandRegistry.macPulseDefaults
        let installer = Installer(appName: app, bundleID: id, registry: registry,
                                  bundledAgentPath: "/Applications/\(app).app/Contents/Resources/agent.sh")
        let text: String
        switch cmd {
        case "agent":
            text = AgentScript(appName: app, registry: registry).render()
        case "plist":
            text = installer.daemon.xml()
        case "install-script":
            text = installer.installShellBody()
        case "uninstall-script":
            text = installer.uninstallShellBody()
        case "verbs":
            text = registry.commands.map { "\($0.verb)\t\($0.description)" }.joined(separator: "\n") + "\n"
        case "help", "-h", "--help":
            printUsage(); return
        default:
            fputs("unknown command \(cmd)\n", stderr); printUsage(); exit(2)
        }
        if let out {
            try text.write(toFile: out, atomically: true, encoding: .utf8)
            print("wrote \(out)")
        } else {
            print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
        }
        _ = filtered
    }

    static func printUsage() {
        fputs("""
        adt-rootagent - generate the passwordless root-agent artifacts

        Usage:
          adt-rootagent agent            [--name App] [--id com.example.app] [-o agent.sh]
          adt-rootagent plist            [--name App] [--id com.example.app]
          adt-rootagent install-script   [--name App] [--id com.example.app]
          adt-rootagent uninstall-script [--name App] [--id com.example.app]
          adt-rootagent verbs

        Security model: request files carry one bare verb and nothing else.
        The agent script and LaunchDaemon ProgramArguments are generated with
        fixed executables and arguments; the spool is world-writable by design
        and that is safe because nothing in a request reaches a shell.

        """, stderr)
    }
}
