#if canImport(CoreGraphics)
import CoreGraphics

public extension Vec2 {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
    init(_ p: CGPoint) { self.init(Double(p.x), Double(p.y)) }
}

public extension MiterRibbon {
    /// Closed CGPath for one facet quad.
    func facetPath(_ i: Int) -> CGPath {
        let q = facets[i]
        let p = CGMutablePath()
        p.addLines(between: q.map(\.cgPoint))
        p.closeSubpath()
        return p
    }

    /// Draw the ribbon the way pulseMark does: thickness layer, shaded facets, creases.
    func draw(in ctx: CGContext, shader: FacetShader, thicknessOffset: Vec2 = Vec2(5, -7),
              thicknessColor: CGColor = CGColor(red: 0.02, green: 0.06, blue: 0.16, alpha: 1)) {
        let out = CGMutablePath()
        out.addLines(between: thicknessOutline(offset: thicknessOffset).map(\.cgPoint))
        out.closeSubpath()
        ctx.addPath(out); ctx.setFillColor(thicknessColor); ctx.fillPath()
        for (i, rgb) in shader.shade(self).enumerated() {
            ctx.addPath(facetPath(i))
            ctx.setFillColor(CGColor(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255, alpha: 1))
            ctx.fillPath()
        }
        for (a, b) in creases { ctx.move(to: a.cgPoint); ctx.addLine(to: b.cgPoint) }
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.24)); ctx.setLineWidth(2); ctx.strokePath()
    }
}
#endif
