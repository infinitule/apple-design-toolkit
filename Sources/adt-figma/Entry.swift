import Foundation
import FigmaKitExtract

@main
enum ADTFigma {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else { printUsage(); exit(2) }
        switch cmd {
        case "extract":
            try extract(Array(args.dropFirst()))
        case "queries":
            guard args.count >= 2 else { printUsage(); exit(2) }
            for q in SearchPlanner.singleTermQueries(args[1]) { print(q) }
        case "check-pages":
            let pages = Array(args.dropFirst())
            switch KitFileCheck.inspect(pages: pages) {
            case .ok: print("ok"); exit(0)
            case .coverOnly: print("cover-only"); exit(1)
            case .empty: print("empty"); exit(1)
            }
        case "help", "-h", "--help": printUsage()
        default:
            fputs("unknown command \(cmd)\n", stderr); printUsage(); exit(2)
        }
    }

    static func extract(_ args: [String]) throws {
        var input: String?
        var output: String?
        var mode: String?
        var required: [String: String] = [:]
        var i = 0
        while i < args.count {
            switch args[i] {
            case "-i", "--input":
                i += 1; input = args[i]
            case "-o", "--output":
                i += 1; output = args[i]
            case "--mode":
                i += 1; mode = args[i]
            case "--select":
                i += 1
                let parts = args[i].split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { throw ExtractError("--select", "expected Key=Value") }
                required[String(parts[0])] = String(parts[1])
            default:
                if input == nil { input = args[i] } else { throw ExtractError(args[i], "unexpected argument") }
            }
            i += 1
        }
        guard let input else { printUsage(); exit(2) }
        let data = try Data(contentsOf: URL(fileURLWithPath: input))
        let json = try JSONValue.parse(data)
        let node = try NodeParser().parse(json)
        let extractor = TokenExtractor(modeName: mode)
        let tokens: [ComponentToken]
        if !required.isEmpty {
            tokens = [try extractor.extract(node, selecting: required)]
        } else {
            tokens = try extractor.extract(node)
        }
        let source = SwiftUIGenerator(namespace: "Kit",
                                      header: "Source: \(input)").generate(tokens)
        if let output {
            try source.write(toFile: output, atomically: true, encoding: .utf8)
            print("wrote \(output) (\(tokens.count) token(s))")
        } else {
            print(source)
        }
    }

    static func printUsage() {
        fputs("""
        adt-figma - Figma kit JSON -> SwiftUI design tokens

        Usage:
          adt-figma extract -i node.json [-o Kit.swift] [--mode Dark] [--select Mode=Dark]
          adt-figma queries "window panel material glass button"
          adt-figma check-pages Cover Components

        """, stderr)
    }
}
