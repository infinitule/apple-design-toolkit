/// Minimal 2D vector so the geometry is platform-neutral (no CoreGraphics).
public struct Vec2: Equatable, Hashable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    public static let zero = Vec2(0, 0)
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }

    public func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    public func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }
    public var length: Double { (x * x + y * y).squareRoot() }

    /// Unit vector, or nil when the vector is (numerically) zero.
    public var normalized: Vec2? {
        let l = length
        return l < 1e-12 ? nil : Vec2(x / l, y / l)
    }

    /// Left-hand perpendicular (-y, x): rotates +90 degrees in a y-up space,
    /// which is a visual -90 (pointing down for a rightward segment) in y-down SVG space.
    public var perpLeft: Vec2 { Vec2(-y, x) }
    /// Right-hand perpendicular (y, -x).
    public var perpRight: Vec2 { Vec2(y, -x) }

    public func isApprox(_ o: Vec2, tol: Double = 1e-9) -> Bool {
        abs(x - o.x) <= tol && abs(y - o.y) <= tol
    }
    public var description: String { "(\(x), \(y))" }
}

public enum Polygon {
    /// Shoelace signed area: positive for counter-clockwise in a y-up space.
    public static func signedArea(_ pts: [Vec2]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var a = 0.0
        for i in pts.indices { a += pts[i].cross(pts[(i + 1) % pts.count]) }
        return a / 2
    }

    /// True when the quad is simple (its two diagonals properly intersect),
    /// i.e. the facet did not fold over itself.
    public static func isConvexQuad(_ q: [Vec2]) -> Bool {
        guard q.count == 4 else { return false }
        var sign = 0.0
        for i in 0..<4 {
            let a = q[i], b = q[(i + 1) % 4], c = q[(i + 2) % 4]
            let z = (b - a).cross(c - b)
            if abs(z) < 1e-12 { continue }
            if sign == 0 { sign = z } else if (z > 0) != (sign > 0) { return false }
        }
        return sign != 0
    }
}
