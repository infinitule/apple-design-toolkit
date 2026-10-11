import Foundation

/// One request file dropped into the spool. The security invariant from the
/// skill: a request contains a single bare verb and nothing else. No paths,
/// no flags, no arguments.
public struct Request: Equatable {
    public var id: String
    public var verb: String
    public var sourcePath: String?

    public enum ParseError: Error, Equatable {
        case emptyFile
        case noVerb
        case emptyId
        case invalidFilename(String)
    }

    /// Sanitize a reply/request id: only alphanumerics, from the skill's
    /// `id="${id//[^a-zA-Z0-9]/}"`. Empty after stripping is rejected.
    public static func sanitizeID(_ raw: String) -> String? {
        let kept = raw.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let s = String(String.UnicodeScalarView(kept))
        return s.isEmpty ? nil : s
    }

    /// Strip everything but lowercase letters, from the skill's
    /// `verb=$(head -1 "$req" | tr -cd 'a-z')`.
    public static func sanitizeVerb(_ raw: String) -> String {
        String(raw.unicodeScalars.filter { $0.value >= 0x61 && $0.value <= 0x7a }.map(Character.init))
    }

    /// Parse `req-<id>` and the first line of its contents.
    public static func parse(filename: String, contents: String) throws -> Request {
        guard filename.hasPrefix("req-") else { throw ParseError.invalidFilename(filename) }
        let rawID = String(filename.dropFirst(4))
        guard let id = sanitizeID(rawID) else { throw ParseError.emptyId }
        // Only the first line, and only before any NUL (defense against
        // binary junk in the world-writable spool).
        let firstLine: String
        if let nul = contents.utf8.firstIndex(of: 0) {
            firstLine = String(contents[..<contents.index(contents.startIndex, offsetBy: contents.utf8.distance(from: contents.utf8.startIndex, to: nul))])
        } else {
            firstLine = contents
        }
        let line = firstLine.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard !line.isEmpty || !firstLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !contents.isEmpty else {
            throw ParseError.emptyFile
        }
        let verb = sanitizeVerb(line)
        guard !verb.isEmpty else { throw ParseError.noVerb }
        return Request(id: id, verb: verb)
    }
}

public struct Reply: Equatable {
    public enum Kind: Equatable {
        case ok
        case path(String)
        case error(String)
    }
    public var id: String
    public var kind: Kind

    /// Filename the agent writes: `done-<id>`.
    public var filename: String { "done-\(id)" }

    /// File contents. Paths are constructed by the agent, never taken from
    /// the request; the reply just reports what the agent produced.
    public var contents: String {
        switch kind {
        case .ok: return "ok"
        case .path(let p): return p
        case .error(let e): return "error: \(e)"
        }
    }

    public static func parse(filename: String, contents: String) throws -> Reply {
        guard filename.hasPrefix("done-") else { throw Request.ParseError.invalidFilename(filename) }
        guard let id = Request.sanitizeID(String(filename.dropFirst(5))) else { throw Request.ParseError.emptyId }
        let body = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if body == "ok" { return Reply(id: id, kind: .ok) }
        if body.hasPrefix("error: ") { return Reply(id: id, kind: .error(String(body.dropFirst(7)))) }
        return Reply(id: id, kind: .path(body))
    }
}
