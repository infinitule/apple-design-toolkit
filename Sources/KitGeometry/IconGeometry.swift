import Foundation

/// macOS (Big Sur and later) icon grid from the skill: an 824 x 824 squircle
/// at (100, 100) with radius 185 on a 1024 canvas; the mark spans ~62% of it.
public struct IconGrid: Equatable {
    public var canvas: Double = 1024
    public var plateOrigin: Double = 100
    public var plateSize: Double = 824
    public var plateRadius: Double = 185
    public var markFraction: Double = 0.62
    public init() {}

    /// Scale the grid to another canvas size, keeping proportions.
    public func scaled(to size: Double) -> IconGrid {
        let k = size / canvas
        var g = self
        g.canvas = size; g.plateOrigin *= k; g.plateSize *= k; g.plateRadius *= k
        return g
    }

    /// Square box the mark should be fitted into, centred on the plate.
    public var markBox: (origin: Vec2, size: Double) {
        let s = plateSize * markFraction
        let o = plateOrigin + (plateSize - s) / 2
        return (Vec2(o, o), s)
    }

    /// Whether a canvas point lies inside the rounded plate. Used to verify an
    /// exported PNG's corners are transparent (the white-card trap), since
    /// `sips -g hasAlpha` only reports that an alpha channel exists.
    public func plateContains(_ p: Vec2) -> Bool {
        let lo = plateOrigin, hi = plateOrigin + plateSize, r = plateRadius
        guard p.x >= lo, p.x <= hi, p.y >= lo, p.y <= hi else { return false }
        let cx = min(max(p.x, lo + r), hi - r), cy = min(max(p.y, lo + r), hi - r)
        return (p - Vec2(cx, cy)).length <= r + 1e-9
    }
}

/// Map a polyline authored in a source coordinate box into a destination
/// box, preserving aspect ratio and optionally flipping y (SVG to CG).
public enum PolylineFit {
    public static func fit(_ pts: [Vec2], into origin: Vec2, size: Vec2, flipY: Bool) -> [Vec2] {
        guard let first = pts.first else { return [] }
        var lo = first, hi = first
        for p in pts { lo = Vec2(min(lo.x, p.x), min(lo.y, p.y)); hi = Vec2(max(hi.x, p.x), max(hi.y, p.y)) }
        let w = max(hi.x - lo.x, 1e-12), h = max(hi.y - lo.y, 1e-12)
        let k = min(size.x / w, size.y / h)
        let ox = origin.x + (size.x - w * k) / 2, oy = origin.y + (size.y - h * k) / 2
        return pts.map { p in
            let y = flipY ? (hi.y - p.y) : (p.y - lo.y)
            return Vec2(ox + (p.x - lo.x) * k, oy + y * k)
        }
    }
}

/// Superellipse |x/a|^n + |y/b|^n = 1, Apple's "continuous" corner family.
/// images.swift uses n = 5 to contrast it with a circular arc.
public enum Superellipse {
    public static func points(center c: Vec2, a: Double, b: Double, n: Double, count: Int) -> [Vec2] {
        precondition(n > 0 && count >= 4)
        return (0..<count).map { i in
            let t = Double(i) / Double(count) * 2 * Double.pi
            let ct = cos(t), st = sin(t)
            let x = a * copysign(pow(abs(ct), 2 / n), ct)
            let y = b * copysign(pow(abs(st), 2 / n), st)
            return Vec2(c.x + x, c.y + y)
        }
    }

    /// Implicit value; 1 on the curve.
    public static func implicit(_ p: Vec2, center c: Vec2, a: Double, b: Double, n: Double) -> Double {
        pow(abs((p.x - c.x) / a), n) + pow(abs((p.y - c.y) / b), n)
    }
}

/// The exact pulse polyline from images.swift (SVG y-down source units).
public enum PulseMark {
    public static let source: [Vec2] = [
        Vec2(230, 553), Vec2(352, 553), Vec2(412, 468), Vec2(464, 608), Vec2(530, 272),
        Vec2(600, 748), Vec2(660, 498), Vec2(722, 553), Vec2(795, 553),
    ]
    /// Half-width in source units (images.swift: h = 28 * scale).
    public static let halfWidth = 28.0
}
