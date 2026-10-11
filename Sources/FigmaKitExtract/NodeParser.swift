/// Stage 1 of the pipeline: Figma JSON to a typed `DesignNode` tree.
///
/// Accepts both shapes the skill produces:
/// - REST / plugin form: `absoluteBoundingBox` or `width`/`height`,
///   `cornerRadius`, `rectangleCornerRadii`, `fills`, `strokes`, `effects`,
///   `children`, `componentPropertyDefinitions`, `boundVariables`.
/// - Compact `use_figma` form from SKILL.md: `w`, `h`, `r`,
///   `fills: [{s: [r,g,b], o}]`, `fx: [{t, r, y, a}]`, `ch`.
public struct NodeParser {
    public struct Options {
        /// Paints and effects with `visible: false` are dropped (Figma keeps them
        /// in the document but does not render them).
        public var dropInvisible = true
        public var maxDepth = 64
        public init() {}
    }
    public var options: Options
    public init(options: Options = .init()) { self.options = options }

    public func parse(_ root: JSONValue) throws -> DesignNode {
        // REST /v1/files/:key/nodes wraps nodes as {nodes: {id: {document: {...}}}};
        // /v1/files/:key returns {document: {...}}.
        var c = Cursor(value: root, path: "$")
        if let doc = c.child("document") { c = doc }
        else if let nodes = c.child("nodes"), let obj = nodes.value.object, obj.count == 1,
                let k = obj.keys.first, let doc = nodes.child(k)?.child("document") { c = doc }
        if c.value["anatomy"] != nil, let a = c.child("anatomy") {
            var node = try parseNode(a, depth: 0)
            if let v = root["variants"]?.array {
                node.variantAxes = VariantMatrix(names: v.compactMap(\.string)).axes
            }
            return node
        }
        return try parseNode(c, depth: 0)
    }

    func parseNode(_ c: Cursor, depth: Int) throws -> DesignNode {
        guard depth <= options.maxDepth else { throw ExtractError(c.path, "tree deeper than \(options.maxDepth)") }
        guard c.value.object != nil else { throw ExtractError(c.path, "expected a node object") }
        let compact = c.value["w"] != nil || c.value["ch"] != nil || c.value["fx"] != nil
        let name = try c.require("name").string()
        let type = try c.child("type")?.string() ?? "FRAME"

        let (w, h): (Double, Double)
        if compact {
            w = try c.require("w").number(); h = try c.require("h").number()
        } else if let bb = c.child("absoluteBoundingBox"), bb.value != .null {
            w = try bb.require("width").number(); h = try bb.require("height").number()
        } else if let s = c.child("size") {
            w = try s.require("x").number(); h = try s.require("y").number()
        } else {
            w = try c.require("width").number(); h = try c.require("height").number()
        }
        guard w >= 0, h >= 0 else { throw ExtractError(c.path, "negative size \(w) x \(h)") }

        let bound = boundFillVariables(c)
        var node = DesignNode(id: c.value["id"]?.string, name: name, type: type, width: w, height: h)
        node.radii = try parseRadii(c, compact: compact)
        node.opacity = try c.optionalNumber("opacity") ?? 1
        if compact {
            node.fills = try (c.child("fills")?.elements() ?? []).map(parseCompactPaint)
            node.effects = try (c.child("fx")?.elements() ?? []).map(parseCompactEffect)
        } else {
            node.fills = try (c.child("fills")?.elements() ?? []).enumerated().compactMap {
                try parsePaint($1, variable: bound[$0])
            }
            node.strokes = try (c.child("strokes")?.elements() ?? []).compactMap { try parsePaint($0, variable: nil) }
            node.strokeWeight = try c.optionalNumber("strokeWeight")
            node.effects = try (c.child("effects")?.elements() ?? []).compactMap(parseEffect)
            node.variantAxes = try parseVariantDefinitions(c)
        }
        let kids = try (c.child(compact ? "ch" : "children")?.elements() ?? [])
        node.children = try kids.map { try parseNode($0, depth: depth + 1) }
        if node.variantAxes.isEmpty, type == "COMPONENT_SET" {
            node.variantAxes = VariantMatrix(names: node.children.map(\.name)).axes
        }
        return node
    }

    func parseRadii(_ c: Cursor, compact: Bool) throws -> CornerRadii {
        if let rc = c.child("rectangleCornerRadii"), rc.value != .null {
            let v = try rc.elements().map { try $0.number() }
            guard v.count == 4 else { throw ExtractError(rc.path, "expected 4 corner radii, got \(v.count)") }
            guard v.allSatisfy({ $0 >= 0 }) else { throw ExtractError(rc.path, "negative radius") }
            return Set(v).count == 1 ? (v[0] == 0 ? .none : .uniform(v[0])) : .perCorner(v)
        }
        if let r = try c.optionalNumber(compact ? "r" : "cornerRadius") {
            guard r >= 0 else { throw ExtractError(c.path, "negative corner radius") }
            return r == 0 ? .none : .uniform(r)
        }
        return .none
    }

    func parseColor(_ c: Cursor, opacity: Double) throws -> RGBA {
        let comps = try ["r", "g", "b"].map { k -> Double in
            let v = try c.require(k).number()
            guard (0...1).contains(v) else { throw ExtractError(c.path + "." + k, "channel \(v) outside 0...1") }
            return v
        }
        let a = try c.optionalNumber("a") ?? 1
        return RGBA(comps[0], comps[1], comps[2], a * opacity)
    }

    func parsePaint(_ c: Cursor, variable: String?) throws -> Paint? {
        if options.dropInvisible, c.optionalBool("visible") == false { return nil }
        let type = try c.require("type").string()
        let opacity = try c.optionalNumber("opacity") ?? 1
        switch type {
        case "SOLID":
            return .solid(try parseColor(try c.require("color"), opacity: opacity), variable: variable)
        case let t where t.hasPrefix("GRADIENT_"):
            let stops = try c.require("gradientStops").elements().map {
                GradientStop(position: try $0.require("position").number(),
                             color: try parseColor(try $0.require("color"), opacity: opacity))
            }
            guard stops.count >= 2 else { throw ExtractError(c.path, "gradient needs at least two stops") }
            return .gradient(kind: String(t.dropFirst("GRADIENT_".count)), stops: stops)
        case "IMAGE": return .image
        default: return .other(type)
        }
    }

    func parseCompactPaint(_ c: Cursor) throws -> Paint {
        if let s = c.child("s") {
            let b = try s.elements().map { try $0.number() }
            guard b.count == 3, b.allSatisfy({ (0...255).contains($0) }) else {
                throw ExtractError(s.path, "expected three 0-255 channels")
            }
            return .solid(RGBA(bytes: b, opacity: try c.optionalNumber("o") ?? 1), variable: nil)
        }
        return .other(try c.child("t")?.string() ?? "UNKNOWN")
    }

    func parseEffect(_ c: Cursor) throws -> Effect? {
        if options.dropInvisible, c.optionalBool("visible") == false { return nil }
        let raw = try c.require("type").string()
        let off = c.child("offset")
        return Effect(kind: EffectKind(rawValue: raw) ?? .other, rawType: raw,
                      radius: try c.optionalNumber("radius") ?? 0,
                      offset: (try off?.optionalNumber("x") ?? 0, try off?.optionalNumber("y") ?? 0),
                      spread: try c.optionalNumber("spread") ?? 0,
                      color: try c.child("color").map { try parseColor($0, opacity: 1) },
                      visible: c.optionalBool("visible") ?? true)
    }

    func parseCompactEffect(_ c: Cursor) throws -> Effect {
        let raw = try c.require("t").string()
        let a = try c.optionalNumber("a")
        return Effect(kind: EffectKind(rawValue: raw) ?? .other, rawType: raw,
                      radius: try c.optionalNumber("r") ?? 0, offset: (0, try c.optionalNumber("y") ?? 0),
                      spread: 0, color: a.map { RGBA(0, 0, 0, $0) }, visible: true)
    }

    func parseVariantDefinitions(_ c: Cursor) throws -> [String: [String]] {
        guard let defs = c.child("componentPropertyDefinitions")?.value.object else { return [:] }
        var axes: [String: [String]] = [:]
        for (k, v) in defs where v["type"]?.string == "VARIANT" {
            axes[k] = v["variantOptions"]?.array?.compactMap(\.string) ?? []
        }
        return axes
    }

    /// `boundVariables.fills[i] = {type: VARIABLE_ALIAS, id}`; also accepted per paint.
    func boundFillVariables(_ c: Cursor) -> [Int: String] {
        var out: [Int: String] = [:]
        if let arr = c.value["boundVariables"]?["fills"]?.array {
            for (i, v) in arr.enumerated() where v["type"]?.string == "VARIABLE_ALIAS" {
                if let id = v["id"]?.string { out[i] = id }
            }
        }
        if let fills = c.value["fills"]?.array {
            for (i, f) in fills.enumerated() {
                if let id = f["boundVariables"]?["color"]?["id"]?.string { out[i] = id }
            }
        }
        return out
    }
}
