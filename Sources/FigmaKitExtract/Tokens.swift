/// Stage 2: typed node tree to design tokens, applying the kit-reading rules
/// from the skill (capsules, stacked translucent fills, specular edge pairs,
/// whisper-soft shadows, variant selection).
public struct ComponentToken: Equatable {
    public enum Shape: Equatable {
        case rectangle
        case capsule
        case rounded(Double)
        case corners([Double])
    }
    public struct Fill: Equatable {
        public var color: RGBA
        /// Variable name when the fill is bound to a kit variable.
        public var variable: String?
    }
    public struct Shadow: Equatable {
        public var inner: Bool
        public var color: RGBA
        public var radius: Double
        public var x: Double
        public var y: Double
        public var spread: Double
    }
    public struct Gradient: Equatable {
        public var kind: String
        public var stops: [GradientStop]
    }

    public var name: String
    public var variant: [String: String]
    public var width: Double
    public var height: Double
    public var shape: Shape
    /// Bottom to top, exactly as Figma paints them. Never average these.
    public var fills: [Fill]
    public var gradients: [Gradient]
    public var stroke: Fill?
    public var strokeWidth: Double
    public var shadows: [Shadow]
    public var backgroundBlur: Double?
    public var hasGlassEffect: Bool
    /// Inner-shadow pair at +y and -y encoding specular top and bottom edges.
    public var specularEdges: (top: Shadow, bottom: Shadow)?
    public var parts: [ComponentToken]
    public var notes: [String]

    public static func == (l: ComponentToken, r: ComponentToken) -> Bool {
        l.name == r.name && l.variant == r.variant && l.width == r.width && l.height == r.height
            && l.shape == r.shape && l.fills == r.fills && l.gradients == r.gradients && l.stroke == r.stroke
            && l.strokeWidth == r.strokeWidth && l.shadows == r.shadows && l.backgroundBlur == r.backgroundBlur
            && l.hasGlassEffect == r.hasGlassEffect && l.specularEdges?.top == r.specularEdges?.top
            && l.specularEdges?.bottom == r.specularEdges?.bottom && l.parts == r.parts && l.notes == r.notes
    }
}

public struct TokenExtractor {
    public var variables: VariableStore?
    /// Mode used when resolving bound variables, e.g. "Dark".
    public var modeName: String?
    /// How deep into children to keep named parts (knob, label, ...).
    public var partDepth = 2

    public init(variables: VariableStore? = nil, modeName: String? = nil) {
        self.variables = variables; self.modeName = modeName
    }

    /// Extract every variant of a component set, or the node itself.
    public func extract(_ node: DesignNode) throws -> [ComponentToken] {
        if node.type == "COMPONENT_SET" {
            return try node.children.map { try token(for: $0, base: node.name, depth: 0) }
        }
        return [try token(for: node, base: nil, depth: 0)]
    }

    /// Extract only the variant matching `required` (see VariantMatrix.select).
    public func extract(_ set: DesignNode, selecting required: [String: String],
                        preferred: [String: String] = [:]) throws -> ComponentToken {
        let m = VariantMatrix(names: set.children.map(\.name))
        let name = try m.select(required: required, preferred: preferred)
        return try token(for: set.children.first { $0.name == name }!, base: set.name, depth: 0)
    }

    func token(for n: DesignNode, base: String?, depth: Int) throws -> ComponentToken {
        let variant = (base != nil ? try? VariantMatrix.properties(of: n.name) : nil) ?? [:]
        var notes: [String] = []
        var fills: [ComponentToken.Fill] = [], grads: [ComponentToken.Gradient] = []
        for p in n.fills {
            switch p {
            case .solid(var c, let varId):
                var varName: String?
                if let varId, let store = variables {
                    varName = store.variables[varId]?.name
                    if case .color(let resolved) = try store.resolve(varId, modeName: modeName) {
                        c = RGBA(resolved.r, resolved.g, resolved.b, resolved.a * c.a)
                    }
                }
                c.a *= n.opacity
                fills.append(.init(color: c, variable: varName))
            case .gradient(let kind, let stops): grads.append(.init(kind: kind, stops: stops))
            case .image: notes.append("image fill skipped: export it as an asset, do not inline")
            case .other(let t): notes.append("unsupported paint \(t) skipped")
            }
        }
        if fills.filter({ $0.color.a < 1 }).count >= 2 {
            notes.append("\(fills.count) stacked translucent fills: layer them, never average into one colour")
        }

        var shadows: [ComponentToken.Shadow] = [], blur: Double?, glass = false
        for e in n.effects where e.visible {
            switch e.kind {
            case .dropShadow, .innerShadow:
                shadows.append(.init(inner: e.kind == .innerShadow, color: e.color ?? RGBA(0, 0, 0, 0.25),
                                     radius: e.radius, x: e.offset.x, y: e.offset.y, spread: e.spread))
            case .backgroundBlur: blur = e.radius
            case .glass: glass = true
            case .layerBlur: notes.append("layer blur \(e.radius) applies to content, not the backdrop")
            case .other: notes.append("unsupported effect \(e.rawType) skipped")
            }
        }
        let edges = Self.specularPair(shadows.filter(\.inner))
        if glass, edges == nil, shadows.contains(where: { $0.inner && $0.y > 0 }) {
            notes.append("glass has a top specular edge but no bottom counter-light: the panel will read as paper")
        }
        if let s = shadows.first(where: { !$0.inner }), s.color.a <= 0.05 {
            notes.append("drop shadow alpha \(s.color.a) is intentionally whisper-soft; do not darken it")
        }

        var stroke: ComponentToken.Fill?
        if case .solid(let c, _)? = n.strokes.first { stroke = .init(color: c, variable: nil) }

        let parts = depth < partDepth
            ? try n.children.filter { $0.type != "TEXT" }.map { try token(for: $0, base: nil, depth: depth + 1) }
            : []
        return ComponentToken(
            name: base ?? n.name, variant: variant, width: n.width, height: n.height,
            shape: Self.shape(n), fills: fills, gradients: grads, stroke: stroke,
            strokeWidth: stroke == nil ? 0 : (n.strokeWeight ?? 1), shadows: shadows, backgroundBlur: blur,
            hasGlassEffect: glass, specularEdges: edges, parts: parts, notes: notes)
    }

    /// Kit buttons are true capsules (cornerRadius 1000): any radius that
    /// reaches half the short side renders as a capsule.
    static func shape(_ n: DesignNode) -> ComponentToken.Shape {
        let half = min(n.width, n.height) / 2
        switch n.radii {
        case .none: return .rectangle
        case .uniform(let r): return r >= half - 0.5 && half > 0 ? .capsule : .rounded(r)
        case .perCorner(let v): return .corners(v.map { min($0, half) })
        }
    }

    /// Find an inner-shadow pair whose y offsets mirror each other (+d / -d).
    static func specularPair(_ inner: [ComponentToken.Shadow]) -> (top: ComponentToken.Shadow, bottom: ComponentToken.Shadow)? {
        for a in inner where a.y > 0 {
            if let b = inner.first(where: { abs($0.y + a.y) < 0.5 }) { return (a, b) }
        }
        return nil
    }
}
