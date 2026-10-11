/// Miter-offset ribbon: the folded-paper icon geometry from
/// `figma-apple-kit-extract` ("Building a parametric icon mark") and
/// `pulseMark` in images.swift, extracted so it can be reused and tested.
///
/// For each interior vertex the offset direction is the miter normal
/// m = normalize(n1 + n2) and the offset length is s = h / dot(m, n1),
/// clamped so sharp reversals do not spike. End vertices use their single
/// segment normal at distance h. Each segment becomes a quad
/// [top_i, top_i+1, bot_i+1, bot_i].
public struct MiterRibbon: Equatable {
    public struct Options: Equatable {
        /// Maximum miter length as a multiple of the half-width h.
        public var miterLimit: Double
        /// When dot(m, n1) falls below this the joint is treated as a sharp
        /// reversal and the clamped length is used directly.
        public var sharpCosine: Double
        public init(miterLimit: Double = 2.4, sharpCosine: Double = 0.35) {
            self.miterLimit = miterLimit
            self.sharpCosine = sharpCosine
        }
        /// The exact constants images.swift uses for the shipped imagery.
        public static let imagesSwift = Options(miterLimit: 2.4, sharpCosine: 0.35)
    }

    public enum BuildError: Error, Equatable {
        case tooFewPoints(Int)
        case nonPositiveHalfWidth(Double)
        case nonFinitePoint(Int)
    }

    /// The polyline after removing consecutive duplicate points.
    public let spine: [Vec2]
    /// Offset vertices on the +normal side and the -normal side.
    public let top: [Vec2]
    public let bottom: [Vec2]
    /// Per-segment offset normal (perpLeft of the segment direction).
    public let segmentNormals: [Vec2]
    /// Per-segment unit direction.
    public let segmentDirections: [Vec2]
    /// Vertex indices whose miter was clamped.
    public let clampedJoints: [Int]

    public init(polyline: [Vec2], halfWidth h: Double, options: Options = .init()) throws {
        guard h > 0, h.isFinite else { throw BuildError.nonPositiveHalfWidth(h) }
        for (i, p) in polyline.enumerated() where !(p.x.isFinite && p.y.isFinite) {
            throw BuildError.nonFinitePoint(i)
        }
        // Zero-length segments have no direction; drop repeated points.
        var pts: [Vec2] = []
        for p in polyline where pts.last.map({ !$0.isApprox(p, tol: 1e-12) }) ?? true { pts.append(p) }
        guard pts.count >= 2 else { throw BuildError.tooFewPoints(pts.count) }

        var dirs: [Vec2] = [], norms: [Vec2] = []
        for i in 0..<(pts.count - 1) {
            let d = (pts[i + 1] - pts[i]).normalized!
            dirs.append(d); norms.append(d.perpLeft)
        }

        var top: [Vec2] = [], bot: [Vec2] = [], clamped: [Int] = []
        let limit = h * options.miterLimit
        for i in pts.indices {
            let m: Vec2, s: Double
            if i == 0 {
                m = norms[0]; s = h
            } else if i == pts.count - 1 {
                m = norms[norms.count - 1]; s = h
            } else if let mm = (norms[i - 1] + norms[i]).normalized {
                let c = mm.dot(norms[i - 1])
                m = mm
                if c < options.sharpCosine || h / c > limit { s = limit; clamped.append(i) }
                else { s = h / c }
            } else {
                // Exact 180 degree reversal: n1 + n2 = 0, the miter is undefined.
                // Square it off along the incoming normal at the clamped length.
                m = norms[i - 1]; s = limit; clamped.append(i)
            }
            top.append(pts[i] + m * s)
            bot.append(pts[i] - m * s)
        }
        self.spine = pts
        self.top = top
        self.bottom = bot
        self.segmentNormals = norms
        self.segmentDirections = dirs
        self.clampedJoints = clamped
    }

    /// One quad per segment: [top_i, top_i+1, bot_i+1, bot_i].
    public var facets: [[Vec2]] {
        (0..<(spine.count - 1)).map { [top[$0], top[$0 + 1], bottom[$0 + 1], bottom[$0]] }
    }

    /// Closed outline: the top edge forward, then the bottom edge reversed.
    /// images.swift draws this once, offset, as the paper-thickness shadow.
    public var outline: [Vec2] { top + bottom.reversed() }

    /// Crease lines at interior fold vertices.
    public var creases: [(Vec2, Vec2)] {
        guard spine.count > 2 else { return [] }
        return (1..<(spine.count - 1)).map { (top[$0], bottom[$0]) }
    }

    /// The outline translated, for the darker "paper thickness" layer drawn
    /// behind the facets (images.swift uses +5, -7 in y-up space).
    public func thicknessOutline(offset: Vec2) -> [Vec2] { outline.map { $0 + offset } }
}
