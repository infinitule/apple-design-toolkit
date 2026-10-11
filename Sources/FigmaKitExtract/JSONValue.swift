import Foundation

/// Untyped JSON tree. Figma payloads are large and loosely versioned, so we
/// decode to this first and then walk it with path-aware accessors; every
/// parse error names the exact JSON path that was wrong.
public enum JSONValue: Equatable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    public var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var number: Double? { if case .number(let d) = self { return d }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
}

public struct ExtractError: Error, Equatable, CustomStringConvertible {
    public let path: String
    public let message: String
    public init(_ path: String, _ message: String) { self.path = path; self.message = message }
    public var description: String { "\(path): \(message)" }
}

/// A cursor into a JSON tree that remembers how it got there.
struct Cursor {
    let value: JSONValue
    let path: String

    func child(_ key: String) -> Cursor? { value[key].map { Cursor(value: $0, path: path + "." + key) } }

    func require(_ key: String) throws -> Cursor {
        guard let c = child(key), c.value != .null else { throw ExtractError(path + "." + key, "missing") }
        return c
    }
    func number() throws -> Double {
        guard let d = value.number, d.isFinite else { throw ExtractError(path, "expected a finite number") }
        return d
    }
    func string() throws -> String {
        guard let s = value.string else { throw ExtractError(path, "expected a string") }
        return s
    }
    func elements() throws -> [Cursor] {
        guard let a = value.array else { throw ExtractError(path, "expected an array") }
        return a.enumerated().map { Cursor(value: $1, path: "\(path)[\($0)]") }
    }
    func optionalNumber(_ key: String) throws -> Double? {
        guard let c = child(key), c.value != .null else { return nil }
        return try c.number()
    }
    func optionalBool(_ key: String) -> Bool? { value[key]?.bool }
}
