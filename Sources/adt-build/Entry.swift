import Foundation
import NoXcodeBuild
import ToolkitCore

@main
enum ADTBuild {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else { printUsage(); exit(2) }
        switch cmd {
        case "plan":
            try plan(Array(args.dropFirst()))
        case "plist":
            try plist(Array(args.dropFirst()))
        case "script":
            try script(Array(args.dropFirst()))
        case "help", "-h", "--help": printUsage()
        default:
            fputs("unknown command \(cmd)\n", stderr); printUsage(); exit(2)
        }
    }

    static func common(_ args: [String]) throws -> (BuildPlan, Bool) {
        var source: String?
        var name = "MyApp"
        var bundleID = "com.example.myapp"
        var dest = FileManager.default.currentDirectoryPath
        var lsUI = true
        var printSteps = false
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--name": i += 1; name = args[i]
            case "--id": i += 1; bundleID = args[i]
            case "--dest": i += 1; dest = args[i]
            case "--dock": lsUI = false
            case "--steps": printSteps = true
            default:
                if source == nil { source = args[i] }
                else { throw BuildPlan.BuildError.invalidDestination(args[i]) }
            }
            i += 1
        }
        guard let source else { printUsage(); exit(2) }
        let info = AppInfo(name: name, bundleID: bundleID, lsUIElement: lsUI)
        return (try BuildPlan(sourcePath: source, info: info, destinationDir: dest), printSteps)
    }

    static func plan(_ args: [String]) throws {
        let (plan, steps) = try common(args)
        print("app: \(plan.appRoot)")
        print("executable: \(plan.bundle.executableRelPath)")
        print("compile: \(plan.compileCommand().joined(separator: " "))")
        print("codesign: \(plan.codesignCommand().joined(separator: " "))")
        if steps {
            for (i, s) in plan.steps().enumerated() {
                switch s {
                case .run(let a): print("\(i). run \(a.joined(separator: " "))")
                case .mkdir(let p): print("\(i). mkdir \(p)")
                case .writeFile(let p, _): print("\(i). write \(p)")
                case .copyFile(let f, let t): print("\(i). cp \(f) -> \(t)")
                case .note(let n): print("\(i). note \(n)")
                }
            }
        }
    }

    static func plist(_ args: [String]) throws {
        let (plan, _) = try common(args)
        print(plan.info.xml(), terminator: "")
    }

    static func script(_ args: [String]) throws {
        let (plan, _) = try common(args)
        print(plan.renderBuildScript(), terminator: "")
    }

    static func printUsage() {
        fputs("""
        adt-build - plan a single-file macOS .app build (no Xcode project)

        Usage:
          adt-build plan  main.swift --name MyApp --id com.example.myapp [--dest DIR] [--steps]
          adt-build plist main.swift --name MyApp --id com.example.myapp
          adt-build script main.swift --name MyApp --id com.example.myapp [--dest DIR]

        Running the compile/codesign steps requires macOS. This CLI emits the
        plan, Info.plist and build.sh so the pure parts can be reviewed anywhere.

        """, stderr)
    }
}
