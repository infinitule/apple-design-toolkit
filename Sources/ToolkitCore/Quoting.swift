import Foundation

/// POSIX shell quoting. Every generated script in this package passes
/// developer-supplied strings through here; no request data ever reaches it.
public enum Shell {
    static let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./=:,+@%")

    /// Quote one word so `sh` reads it back byte for byte.
    public static func quote(_ s: String) -> String {
        if !s.isEmpty, s.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Join argv into one command line.
    public static func join(_ argv: [String]) -> String {
        argv.map(quote).joined(separator: " ")
    }
}

/// AppleScript string-literal escaping for
/// `osascript -e 'do shell script "..." with administrator privileges'`.
public enum AppleScript {
    public static func stringLiteral(_ s: String) -> String {
        var r = "\""
        for c in s {
            switch c {
            case "\\": r += "\\\\"
            case "\"": r += "\\\""
            default: r.append(c)
            }
        }
        return r + "\""
    }

    /// The single GUI admin prompt. Returns argv for /usr/bin/osascript.
    /// Exit status 1 from osascript means the user pressed Cancel.
    public static func adminShellScriptArgv(_ shellCommand: String, prompt: String? = nil) -> [String] {
        var script = "do shell script \(stringLiteral(shellCommand)) with administrator privileges"
        if let prompt { script += " with prompt \(stringLiteral(prompt))" }
        return ["/usr/bin/osascript", "-e", script]
    }
}

/// Validation for names that end up inside filesystem paths, launchd labels
/// and generated scripts. Rejecting here is what lets the generators embed
/// them without further escaping decisions.
public enum Identifier {
    public enum Problem: Error, Equatable, CustomStringConvertible {
        case empty(String)
        case tooLong(String, Int)
        case invalidCharacter(String, Character)
        case malformed(String, String)

        public var description: String {
            switch self {
            case .empty(let f): return "\(f) is empty"
            case .tooLong(let f, let n): return "\(f) exceeds \(n) characters"
            case .invalidCharacter(let f, let c): return "\(f) contains invalid character \(String(reflecting: c))"
            case .malformed(let f, let why): return "\(f) is malformed: \(why)"
            }
        }
    }

    /// Reverse-DNS identifier (CFBundleIdentifier, launchd Label):
    /// alphanumerics, hyphen and dot; at least two components; no empty components.
    public static func validateReverseDNS(_ s: String, field: String = "identifier") throws {
        guard !s.isEmpty else { throw Problem.empty(field) }
        guard s.count <= 155 else { throw Problem.tooLong(field, 155) }
        for c in s where !(c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == ".")) {
            throw Problem.invalidCharacter(field, c)
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { throw Problem.malformed(field, "needs at least two dot-separated components") }
        guard !parts.contains(where: \.isEmpty) else { throw Problem.malformed(field, "empty component") }
    }

    /// A single path component that is safe to put under /Library or inside a
    /// bundle: letters, digits, space, hyphen, underscore, dot; never "." or "..";
    /// no leading dot or hyphen (hidden files, option injection).
    public static func validatePathComponent(_ s: String, field: String = "name", maxLength: Int = 64) throws {
        guard !s.isEmpty else { throw Problem.empty(field) }
        guard s.count <= maxLength else { throw Problem.tooLong(field, maxLength) }
        for c in s where !(c.isASCII && (c.isLetter || c.isNumber || " -_.".contains(c))) {
            throw Problem.invalidCharacter(field, c)
        }
        if s.hasPrefix(".") || s.hasPrefix("-") { throw Problem.malformed(field, "must not start with '.' or '-'") }
        if s.hasSuffix(" ") { throw Problem.malformed(field, "must not end with a space") }
    }
}
