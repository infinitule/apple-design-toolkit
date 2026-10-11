/// Figma variables (REST `GET /v1/files/:key/variables/local` shape, or the
/// plugin API's `valuesByMode`). Values are often `VARIABLE_ALIAS` chains,
/// which the skill warns about; this resolves them per mode.
public struct VariableStore {
    public enum Value: Equatable {
        case number(Double)
        case color(RGBA)
        case string(String)
        case bool(Bool)
        case alias(String)
    }
    public struct Variable: Equatable {
        public var id: String
        public var name: String
        public var collectionId: String
        public var valuesByMode: [String: Value]
    }
    public struct Collection: Equatable {
        public var id: String
        public var name: String
        public var defaultModeId: String
        /// modeId to mode name
        public var modes: [String: String]
    }
    public enum ResolveError: Error, Equatable {
        case unknownVariable(String)
        case noValue(variable: String, mode: String)
        case cycle([String])
        case tooDeep(String)
    }

    public private(set) var variables: [String: Variable] = [:]
    public private(set) var collections: [String: Collection] = [:]

    public init(variables: [Variable], collections: [Collection]) {
        for v in variables { self.variables[v.id] = v }
        for c in collections { self.collections[c.id] = c }
    }

    public init(json root: JSONValue) throws {
        let base = Cursor(value: root, path: "$")
        let meta = base.child("meta") ?? base
        for c in try collectionCursors(meta) {
            let id = try c.require("id").string()
            var modes: [String: String] = [:]
            for m in try c.child("modes")?.elements() ?? [] {
                modes[try m.require("modeId").string()] = try m.child("name")?.string() ?? ""
            }
            let def = try c.child("defaultModeId")?.string() ?? modes.keys.sorted().first ?? ""
            collections[id] = Collection(id: id, name: try c.child("name")?.string() ?? id,
                                         defaultModeId: def, modes: modes)
        }
        guard let vars = meta.child("variables") else { throw ExtractError(meta.path + ".variables", "missing") }
        for (key, raw) in vars.value.object ?? [:] {
            let c = Cursor(value: raw, path: vars.path + "." + key)
            let id = try c.child("id")?.string() ?? key
            var values: [String: Value] = [:]
            if let vbm = c.child("valuesByMode"), let obj = vbm.value.object {
                for (mode, v) in obj { values[mode] = try Self.parseValue(Cursor(value: v, path: vbm.path + "." + mode)) }
            }
            variables[id] = Variable(id: id, name: try c.require("name").string(),
                                     collectionId: try c.child("variableCollectionId")?.string() ?? "", valuesByMode: values)
        }
    }

    private func collectionCursors(_ meta: Cursor) throws -> [Cursor] {
        guard let vc = meta.child("variableCollections"), let obj = vc.value.object else { return [] }
        return obj.keys.sorted().map { Cursor(value: obj[$0]!, path: vc.path + "." + $0) }
    }

    static func parseValue(_ c: Cursor) throws -> Value {
        switch c.value {
        case .number(let d): return .number(d)
        case .string(let s): return .string(s)
        case .bool(let b): return .bool(b)
        case .object(let o):
            if o["type"]?.string == "VARIABLE_ALIAS" { return .alias(try c.require("id").string()) }
            if o["r"] != nil { return .color(try NodeParser().parseColor(c, opacity: 1)) }
            throw ExtractError(c.path, "unrecognised variable value")
        default: throw ExtractError(c.path, "unrecognised variable value")
        }
    }

    public func variable(named name: String) -> Variable? {
        variables.values.first { $0.name == name }
    }

    /// Resolve a variable to a concrete value for a mode name (e.g. "Dark").
    /// Aliases may cross collections; when the target collection has no mode
    /// with the same name, its default mode is used, as Figma does.
    public func resolve(_ id: String, modeName: String? = nil) throws -> Value {
        var seen: [String] = []
        var current = id
        var wanted = modeName
        while true {
            if seen.contains(current) { throw ResolveError.cycle(seen + [current]) }
            if seen.count >= 32 { throw ResolveError.tooDeep(id) }
            seen.append(current)
            guard let v = variables[current] else { throw ResolveError.unknownVariable(current) }
            let mode = modeId(for: v, modeName: wanted)
            guard let value = v.valuesByMode[mode] ?? v.valuesByMode.sorted(by: { $0.key < $1.key }).first?.value else {
                throw ResolveError.noValue(variable: v.name, mode: mode)
            }
            if case .alias(let next) = value {
                if wanted == nil, let c = collections[v.collectionId] { wanted = c.modes[mode] }
                current = next
                continue
            }
            return value
        }
    }

    func modeId(for v: Variable, modeName: String?) -> String {
        guard let c = collections[v.collectionId] else { return v.valuesByMode.keys.sorted().first ?? "" }
        if let modeName, let hit = c.modes.first(where: { $0.value == modeName }) { return hit.key }
        return c.defaultModeId
    }
}
