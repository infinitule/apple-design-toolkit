/// Piecewise-linear colour ramp over t in [0, 1], RGB components 0...255.
public struct ColorRamp: Equatable {
    public struct Stop: Equatable {
        public var position: Double
        public var rgb: [Double]
        public init(_ position: Double, _ rgb: [Double]) { self.position = position; self.rgb = rgb }
    }
    public enum RampError: Error, Equatable {
        case needsTwoStops
        case unsorted(Int)
        case badComponentCount(Int)
        case outOfRange(Int)
    }
    public let stops: [Stop]

    public init(_ stops: [Stop]) throws {
        guard stops.count >= 2 else { throw RampError.needsTwoStops }
        for (i, s) in stops.enumerated() {
            guard s.rgb.count == 3 else { throw RampError.badComponentCount(i) }
            guard (0...1).contains(s.position) else { throw RampError.outOfRange(i) }
            if i > 0, s.position < stops[i - 1].position { throw RampError.unsorted(i) }
        }
        self.stops = stops
    }

    /// The blue ramp pulseMark uses.
    public static let pulseBlue = try! ColorRamp([
        Stop(0, [26, 86, 170]), Stop(0.34, [41, 128, 235]),
        Stop(0.66, [125, 205, 255]), Stop(1, [255, 255, 255]),
    ])

    public func sample(_ t: Double) -> [Double] {
        let t = min(1, max(0, t.isNaN ? 0 : t))
        for k in 0..<(stops.count - 1) where t <= stops[k + 1].position || k == stops.count - 2 {
            let a = stops[k], b = stops[k + 1]
            let span = b.position - a.position
            let f = span <= 0 ? 1 : min(1, max(0, (t - a.position) / span))
            return (0..<3).map { a.rgb[$0] + (b.rgb[$0] - a.rgb[$0]) * f }
        }
        return stops[stops.count - 1].rgb
    }
}

/// Per-facet normal shading: t = (dot(n, L) + 1) / 2 mapped through a ramp.
public struct FacetShader {
    public enum Space { case yUp, yDown }
    /// Which perpendicular of a segment direction counts as its lit normal.
    public enum NormalRule: Equatable {
        /// The perpendicular that faces visually up for a left-to-right segment
        /// in the given space. In y-down (SVG) space that is (dy, -dx), the
        /// sign fix the skill calls out; in y-up (CoreGraphics) it is (-dy, dx).
        case upward(Space)
        /// Always (dy, -dx), regardless of space. images.swift applies this in
        /// its flipped y-up context, so its flat horizontals face away from a
        /// top-left light and render in the darker part of the ramp.
        case perpRight
    }
    public let light: Vec2
    public let ramp: ColorRamp
    public let rule: NormalRule

    /// `light` points toward the light source and is normalized here.
    public init(light: Vec2, ramp: ColorRamp = .pulseBlue, rule: NormalRule = .upward(.yUp)) {
        self.light = light.normalized ?? Vec2(0, 1)
        self.ramp = ramp
        self.rule = rule
    }

    /// Reproduces pulseMark's shading in images.swift exactly.
    public static let imagesSwift = FacetShader(light: Vec2(-0.55, 0.83), rule: .perpRight)

    public func litNormal(direction d: Vec2) -> Vec2 {
        switch rule {
        case .upward(.yDown), .perpRight: return d.perpRight
        case .upward(.yUp): return d.perpLeft
        }
    }

    public func intensity(direction d: Vec2) -> Double {
        (litNormal(direction: d).dot(light) + 1) / 2
    }

    public func shade(_ ribbon: MiterRibbon) -> [[Double]] {
        ribbon.segmentDirections.map { ramp.sample(intensity(direction: $0)) }
    }
}
