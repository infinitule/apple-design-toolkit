import Foundation

/// A property-list value. Dictionaries keep keys sorted on output so the
/// generated Info.plist and LaunchDaemon plists are byte-stable across runs
/// (diffable in git, reproducible in CI).
public indirect enum PlistValue: Equatable {
    case string(String)
    case bool(Bool)
    case integer(Int)
    case real(Double)
    case array([PlistValue])
    case dict([String: PlistValue])
}

extension PlistValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
                      ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral,
                      ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .integer(value) }
    public init(arrayLiteral elements: PlistValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, PlistValue)...) {
        var d: [String: PlistValue] = [:]
        for (k, v) in elements { d[k] = v }
        self = .dict(d)
    }
}

/// Deterministic XML property-list writer (Apple's PropertyList-1.0 DTD).
public enum PlistWriter {
    public static func xml(_ root: PlistValue) -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">

        """
        write(root, indent: 0, into: &out)
        out += "</plist>\n"
        return out
    }

    private static func write(_ v: PlistValue, indent: Int, into out: inout String) {
        let pad = String(repeating: "\t", count: indent)
        switch v {
        case .string(let s): out += "\(pad)<string>\(escape(s))</string>\n"
        case .bool(let b): out += "\(pad)<\(b ? "true" : "false")/>\n"
        case .integer(let i): out += "\(pad)<integer>\(i)</integer>\n"
        case .real(let d):
            precondition(d.isFinite, "property lists cannot encode non-finite reals")
            out += "\(pad)<real>\(formatReal(d))</real>\n"
        case .array(let a):
            if a.isEmpty { out += "\(pad)<array/>\n"; return }
            out += "\(pad)<array>\n"
            for e in a { write(e, indent: indent + 1, into: &out) }
            out += "\(pad)</array>\n"
        case .dict(let d):
            if d.isEmpty { out += "\(pad)<dict/>\n"; return }
            out += "\(pad)<dict>\n"
            for k in d.keys.sorted() {
                out += "\(pad)\t<key>\(escape(k))</key>\n"
                write(d[k]!, indent: indent + 1, into: &out)
            }
            out += "\(pad)</dict>\n"
        }
    }

    static func formatReal(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }

    /// XML text escaping. Control characters other than tab/LF/CR are not
    /// representable in XML 1.0, so they are rejected rather than silently dropped.
    public static func escape(_ s: String) -> String {
        var r = ""
        r.reserveCapacity(s.count)
        for u in s.unicodeScalars {
            switch u {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            default:
                precondition(u.value >= 0x20 || u == "\t" || u == "\n" || u == "\r",
                             "control character U+\(String(u.value, radix: 16)) cannot appear in a plist")
                r.unicodeScalars.append(u)
            }
        }
        return r
    }
}
