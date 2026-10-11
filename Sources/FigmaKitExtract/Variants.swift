import Foundation

/// Component-set variants. Kit components ship names like
/// "Mode=Dark, Size=Medium, State=Idle". Taking `defaultVariant` is how a dark
/// control ends up invisible on a dark backdrop; select explicitly instead.
public struct VariantMatrix: Equatable {
    public enum ParseError: Error, Equatable {
        case malformedPair(String)
        case duplicateProperty(String)
    }

    /// Parse one variant name into property to value.
    public static func properties(of name: String) throws -> [String: String] {
        var out: [String: String] = [:]
        for raw in name.split(separator: ",") {
            let pair = raw.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty else { throw ParseError.malformedPair(String(raw)) }
            guard out[pair[0]] == nil else { throw ParseError.duplicateProperty(pair[0]) }
            out[pair[0]] = pair[1]
        }
        return out
    }

    public let variants: [(name: String, props: [String: String])]
    /// Property to its options, in first-seen order.
    public let axes: [String: [String]]

    public init(names: [String]) {
        var vs: [(String, [String: String])] = []
        var axes: [String: [String]] = [:]
        for n in names {
            guard let p = try? Self.properties(of: n) else { continue }
            vs.append((n, p))
            for (k, v) in p where !(axes[k]?.contains(v) ?? false) { axes[k, default: []].append(v) }
        }
        self.variants = vs
        self.axes = axes
    }

    public static func == (l: VariantMatrix, r: VariantMatrix) -> Bool {
        l.axes == r.axes && l.variants.map(\.name) == r.variants.map(\.name)
    }

    /// Combinations in the full cross product that the set does not ship.
    public var missingCombinations: [[String: String]] {
        let keys = axes.keys.sorted()
        var combos: [[String: String]] = [[:]]
        for k in keys {
            combos = combos.flatMap { base in axes[k]!.map { var b = base; b[k] = $0; return b } }
        }
        let present = Set(variants.map { $0.props })
        return combos.filter { !present.contains($0) }
    }

    public enum SelectError: Error, Equatable {
        case unknownProperty(String)
        case unknownValue(property: String, value: String)
        case noMatch([String: String])
    }

    /// Pick the variant that satisfies every `required` property, then matches
    /// the most `preferred` ones; ties go to declaration order.
    public func select(required: [String: String], preferred: [String: String] = [:]) throws -> String {
        for (k, v) in required {
            guard let opts = axes[k] else { throw SelectError.unknownProperty(k) }
            guard opts.contains(v) else { throw SelectError.unknownValue(property: k, value: v) }
        }
        let candidates = variants.filter { v in required.allSatisfy { v.props[$0.key] == $0.value } }
        guard !candidates.isEmpty else { throw SelectError.noMatch(required) }
        var best = candidates[0], bestScore = -1
        for c in candidates {
            let score = preferred.filter { c.props[$0.key] == $0.value }.count
            if score > bestScore { best = c; bestScore = score }
        }
        return best.name
    }
}

/// The kit search matcher (`search_design_system`) is single-term: a
/// multi-word query silently returns nothing. Split into one query per concept.
public enum SearchPlanner {
    static let stop: Set<String> = ["a", "an", "the", "and", "or", "of", "for", "with", "in", "on", "to"]

    public static func singleTermQueries(_ query: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        let words = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        for w in words where !stop.contains(w) {
            let term = singular(w)
            if seen.insert(term).inserted { out.append(term) }
        }
        return out
    }

    static func singular(_ w: String) -> String {
        if w.count > 4, w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.count > 3, w.hasSuffix("es"), ["ss", "sh", "ch", "x"].contains(where: { w.dropLast(2).hasSuffix($0) }) {
            return String(w.dropLast(2))
        }
        if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") { return String(w.dropLast()) }
        return w
    }
}

/// Guards from the skill's prerequisites.
public enum KitFileCheck {
    public enum Verdict: Equatable {
        case ok
        /// A community duplicate that only contains the Cover page.
        case coverOnly
        case empty
    }
    /// `pages` from `get_metadata` without a nodeId.
    public static func inspect(pages: [String]) -> Verdict {
        if pages.isEmpty { return .empty }
        if pages.count == 1, pages[0].trimmingCharacters(in: .whitespaces).lowercased() == "cover" { return .coverOnly }
        return .ok
    }
}
