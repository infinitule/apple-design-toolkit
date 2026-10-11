import Foundation

/// Linear sRGB-encoded colour, components 0...1 as Figma stores them.
public struct RGBA: Equatable, Hashable {
    public var r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    /// From the compact MCP form: 0-255 integer channels plus opacity.
    public init(bytes: [Double], opacity: Double) {
        self.init(bytes[0] / 255, bytes[1] / 255, bytes[2] / 255, opacity)
    }
    /// The skill's `f.color.r * 255 | 0` (truncating) byte conversion.
    public var bytes: [Int] { [r, g, b].map { Int(($0 * 255).rounded(.towardZero)) } }
    public var hex: String {
        let v = [r, g, b].map { Int(($0 * 255).rounded()) }
        return "#" + v.map { String(format: "%02X", min(255, max(0, $0))) }.joined()
    }
}

public struct GradientStop: Equatable {
    public var position: Double
    public var color: RGBA
}

public enum Paint: Equatable {
    case solid(RGBA, variable: String?)
    case gradient(kind: String, stops: [GradientStop])
    case image
    case other(String)

    /// Effective colour for a solid paint (paint opacity folded into alpha).
    public var solidColor: RGBA? { if case .solid(let c, _) = self { return c }; return nil }
}

public enum EffectKind: String, Equatable {
    case dropShadow = "DROP_SHADOW"
    case innerShadow = "INNER_SHADOW"
    case layerBlur = "LAYER_BLUR"
    case backgroundBlur = "BACKGROUND_BLUR"
    case glass = "GLASS"
    case other
}

public struct Effect: Equatable {
    public var kind: EffectKind
    public var rawType: String
    public var radius: Double
    public var offset: (x: Double, y: Double)
    public var spread: Double
    public var color: RGBA?
    public var visible: Bool

    public static func == (l: Effect, r: Effect) -> Bool {
        l.kind == r.kind && l.rawType == r.rawType && l.radius == r.radius && l.offset.x == r.offset.x
            && l.offset.y == r.offset.y && l.spread == r.spread && l.color == r.color && l.visible == r.visible
    }
}

public enum CornerRadii: Equatable {
    case none
    case uniform(Double)
    /// topLeft, topRight, bottomRight, bottomLeft (Figma's rectangleCornerRadii order).
    case perCorner([Double])
}

public struct DesignNode: Equatable {
    public var id: String?
    public var name: String
    public var type: String
    public var width: Double
    public var height: Double
    public var radii: CornerRadii
    public var fills: [Paint]
    public var strokes: [Paint]
    public var strokeWeight: Double?
    public var effects: [Effect]
    public var opacity: Double
    public var children: [DesignNode]
    /// Variant property definitions on a COMPONENT_SET, e.g. Mode: [Dark, Light].
    public var variantAxes: [String: [String]]

    public init(id: String? = nil, name: String, type: String, width: Double, height: Double,
                radii: CornerRadii = .none, fills: [Paint] = [], strokes: [Paint] = [],
                strokeWeight: Double? = nil, effects: [Effect] = [], opacity: Double = 1,
                children: [DesignNode] = [], variantAxes: [String: [String]] = [:]) {
        self.id = id; self.name = name; self.type = type; self.width = width; self.height = height
        self.radii = radii; self.fills = fills; self.strokes = strokes; self.strokeWeight = strokeWeight
        self.effects = effects; self.opacity = opacity; self.children = children; self.variantAxes = variantAxes
    }

    /// Depth-first search by name.
    public func first(named n: String) -> DesignNode? {
        if name == n { return self }
        for c in children { if let f = c.first(named: n) { return f } }
        return nil
    }
}
