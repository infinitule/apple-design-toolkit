import AppKit
import CoreImage

// Renders the repo's imagery. Every control here is drawn from the values
// figma-apple-kit-extract pulls out of Apple's macOS 27 UI Kit, so the
// artwork is the toolkit's own output.
//   assets/banner.png     hero: Figma design system -> native macOS code
//   assets/precision.png  eyeballed vs measured, with the deltas
//   assets/layers.png     the Button's four-fill glass stack, exploded
// Usage: swift images.swift

let dir = FileManager.default.currentDirectoryPath + "/assets"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let space = CGColorSpaceCreateDeviceRGB()

let figmaColors = [
    NSColor(red: 0.949, green: 0.306, blue: 0.118, alpha: 1),  // F24E1E
    NSColor(red: 1.000, green: 0.447, blue: 0.384, alpha: 1),  // FF7262
    NSColor(red: 0.635, green: 0.349, blue: 1.000, alpha: 1),  // A259FF
    NSColor(red: 0.102, green: 0.737, blue: 0.996, alpha: 1),  // 1ABCFE
    NSColor(red: 0.039, green: 0.812, blue: 0.514, alpha: 1)   // 0ACF83
]
let blue = NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)
let ink = NSColor(red: 0.06, green: 0.09, blue: 0.14, alpha: 1)
let warn = NSColor(red: 0.85, green: 0.24, blue: 0.20, alpha: 1)

func capsulePath(_ r: CGRect) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: r.height/2, cornerHeight: r.height/2, transform: nil)
}
func rounded(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

final class Canvas {
    let W: CGFloat, H: CGFloat
    let rep: NSBitmapImageRep
    let ctx: CGContext
    init(_ w: CGFloat, _ h: CGFloat) {
        W = w; H = h
        rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        ctx = NSGraphicsContext.current!.cgContext
    }
    func y(_ top: CGFloat, _ h: CGFloat = 0) -> CGFloat { H - top - h }
    func text(_ s: String, _ x: CGFloat, _ top: CGFloat, _ size: CGFloat,
              _ weight: NSFont.Weight, _ color: NSColor, mono: Bool = false) {
        let f = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                     : NSFont.systemFont(ofSize: size, weight: weight)
        let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color])
        str.draw(at: NSPoint(x: x, y: y(top, str.size().height)))
    }
    func textW(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, mono: Bool = false) -> CGFloat {
        let f = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
                     : NSFont.systemFont(ofSize: size, weight: weight)
        return NSAttributedString(string: s, attributes: [.font: f]).size().width
    }
    func navy() {
        let g = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.055, green: 0.098, blue: 0.180, alpha: 1),
            CGColor(red: 0.024, green: 0.043, blue: 0.094, alpha: 1)] as CFArray, locations: [0,1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: W*0.5, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    func bloom(_ x: CGFloat, _ yy: CGFloat, _ r: CGFloat, _ c: NSColor, _ a: CGFloat) {
        let cc = c.withAlphaComponent(a).cgColor
        let g = CGGradient(colorsSpace: space, colors: [cc, cc.copy(alpha: 0)!] as CFArray, locations: [0,1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: yy), startRadius: 0,
                               endCenter: CGPoint(x: x, y: yy), endRadius: r, options: [])
    }
    func sheet(_ x: CGFloat, _ w: CGFloat, grid: Bool = true) {
        ctx.setFillColor(CGColor(red: 0.945, green: 0.953, blue: 0.965, alpha: 1))
        ctx.fill(CGRect(x: x, y: 0, width: w, height: H))
        guard grid else { return }
        ctx.setStrokeColor(CGColor(red: 0.42, green: 0.52, blue: 0.68, alpha: 0.11))
        ctx.setLineWidth(1)
        for gx in stride(from: x, through: x + w, by: 50) {
            ctx.move(to: CGPoint(x: gx, y: 0)); ctx.addLine(to: CGPoint(x: gx, y: H))
        }
        for gy in stride(from: 0, through: H, by: 50) {
            ctx.move(to: CGPoint(x: x, y: gy)); ctx.addLine(to: CGPoint(x: x + w, y: gy))
        }
        ctx.strokePath()
    }
    /// macOS 27 Switch drawn from measured kit values, at scale s.
    @discardableResult
    func kitSwitch(_ x: CGFloat, _ top: CGFloat, _ s: CGFloat, on: Bool = true) -> CGRect {
        let r = CGRect(x: x, y: y(top, 24*s), width: 54*s, height: 24*s)
        ctx.addPath(capsulePath(r))
        ctx.setFillColor(on ? CGColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1)
                            : CGColor(gray: 0, alpha: 0.85))
        ctx.fillPath()
        let kw = 32*s, kh = 20*s
        let k = CGRect(x: on ? r.maxX - kw - 2*s : r.minX + 2*s, y: r.midY - kh/2, width: kw, height: kh)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3*s), blur: 8*s,
                      color: CGColor(gray: 0, alpha: 0.16))
        ctx.addPath(capsulePath(k)); ctx.setFillColor(.white); ctx.fillPath()
        ctx.restoreGState()
        return r
    }
    func hDim(_ x1: CGFloat, _ x2: CGFloat, _ top: CGFloat, _ c: NSColor) {
        let yy = y(top)
        ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: x1, y: yy)); ctx.addLine(to: CGPoint(x: x2, y: yy))
        for x in [x1, x2] { ctx.move(to: CGPoint(x: x, y: yy-9)); ctx.addLine(to: CGPoint(x: x, y: yy+9)) }
        ctx.strokePath()
    }
    func vDim(_ x: CGFloat, _ t1: CGFloat, _ t2: CGFloat, _ c: NSColor) {
        let y1 = y(t1), y2 = y(t2)
        ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: x, y: y1)); ctx.addLine(to: CGPoint(x: x, y: y2))
        for yy in [y1, y2] { ctx.move(to: CGPoint(x: x-9, y: yy)); ctx.addLine(to: CGPoint(x: x+9, y: yy)) }
        ctx.strokePath()
    }
    func save(_ name: String) {
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: dir + "/" + name))
        print("\(name)  \(Int(W))x\(Int(H))")
    }
}

// ===========================================================================
// 1. BANNER — Figma design system → native macOS code
// ===========================================================================
do {
    let c = Canvas(2400, 1000)
    c.navy()
    c.bloom(250, 780, 900, NSColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1), 0.20)
    c.bloom(1200, 120, 700, figmaColors[2], 0.13)

    c.text("Apple Design Toolkit", 130, 258, 92, .bold, .white)
    c.text("Read Apple's real design system out of Figma.", 134, 408, 41, .medium, NSColor(white: 1, alpha: 0.66))
    c.text("Ship it as native macOS code.", 134, 464, 41, .medium, NSColor(white: 1, alpha: 0.66))
    for (i, s) in ["figma-apple-kit-extract", "macos-app-no-xcode", "passwordless-root-agent"].enumerated() {
        let top = 600 + CGFloat(i) * 80
        let r = CGRect(x: 134, y: c.y(top, 58), width: 590, height: 58)
        c.ctx.addPath(capsulePath(r)); c.ctx.setFillColor(CGColor(gray: 1, alpha: 0.07)); c.ctx.fillPath()
        c.ctx.addPath(capsulePath(r)); c.ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
        c.ctx.setLineWidth(1.5); c.ctx.strokePath()
        c.text(s, 172, top + 14, 27, .medium, NSColor(red: 0.42, green: 0.78, blue: 1, alpha: 1))
    }

    // --- the bridge: Figma tokens → measured values → native control ---
    let bx: CGFloat = 1120
    c.text("F I G M A   L I B R A R Y", bx, 214, 22, .semibold, NSColor(white: 1, alpha: 0.42))
    for (i, col) in figmaColors.enumerated() {
        let r = CGRect(x: bx + CGFloat(i) * 60, y: c.y(260, 48), width: 48, height: 48)
        c.ctx.addPath(rounded(r, 13)); c.ctx.setFillColor(col.cgColor); c.ctx.fillPath()
    }
    let specs = ["track  54 × 24", "knob   32 × 20", "radius 1000", "shadow r15 y8 a.02"]
    for (i, s) in specs.enumerated() {
        c.text(s, bx, 356 + CGFloat(i) * 42, 24, .regular, NSColor(white: 1, alpha: 0.5), mono: true)
    }

    // arrow
    let ay = c.y(430)
    c.ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.28)); c.ctx.setLineWidth(3)
    c.ctx.move(to: CGPoint(x: bx + 310, y: ay)); c.ctx.addLine(to: CGPoint(x: bx + 410, y: ay))
    c.ctx.move(to: CGPoint(x: bx + 410, y: ay)); c.ctx.addLine(to: CGPoint(x: bx + 390, y: ay + 13))
    c.ctx.move(to: CGPoint(x: bx + 410, y: ay)); c.ctx.addLine(to: CGPoint(x: bx + 390, y: ay - 13))
    c.ctx.strokePath()

    // native side: a real macOS surface
    let px: CGFloat = 1580
    c.text("N A T I V E   m a c O S", px, 214, 22, .semibold, NSColor(white: 1, alpha: 0.42))
    let panel = CGRect(x: px, y: c.y(258, 420), width: 700, height: 420)
    c.ctx.saveGState()
    c.ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: CGColor(gray: 0, alpha: 0.5))
    c.ctx.addPath(rounded(panel, 34))
    c.ctx.setFillColor(CGColor(red: 0.13, green: 0.16, blue: 0.22, alpha: 0.96))
    c.ctx.fillPath()
    c.ctx.restoreGState()
    c.ctx.saveGState(); c.ctx.addPath(rounded(panel, 34)); c.ctx.clip()
    let sheen = CGGradient(colorsSpace: space, colors: [
        CGColor(gray: 1, alpha: 0.20), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0,1])!
    c.ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: panel.maxY),
                             end: CGPoint(x: 0, y: panel.maxY - 130), options: [])
    c.ctx.restoreGState()
    c.ctx.addPath(rounded(panel.insetBy(dx: 0.75, dy: 0.75), 34))
    c.ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22)); c.ctx.setLineWidth(1.5); c.ctx.strokePath()
    for (i, col) in [NSColor(red: 1, green: 0.373, blue: 0.341, alpha: 1),
                     NSColor(red: 1, green: 0.737, blue: 0.180, alpha: 1),
                     NSColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1)].enumerated() {
        let d: CGFloat = 22
        let r = CGRect(x: panel.minX + 30 + CGFloat(i) * 34, y: panel.maxY - 52, width: d, height: d)
        c.ctx.addPath(CGPath(ellipseIn: r, transform: nil)); c.ctx.setFillColor(col.cgColor); c.ctx.fillPath()
    }
    c.kitSwitch(panel.minX + 46, 380, 3.0)
    c.text("Toggles — Switches, at kit metrics", panel.minX + 46, 470, 24, .medium, NSColor(white: 1, alpha: 0.5))
    for (i, label) in ["Audit", "Tune"].enumerated() {
        let r = CGRect(x: panel.minX + 46 + CGFloat(i) * 220, y: c.y(540, 92), width: 196, height: 92)
        c.ctx.addPath(capsulePath(r)); c.ctx.setFillColor(CGColor(gray: 1, alpha: 0.10)); c.ctx.fillPath()
        c.ctx.addPath(capsulePath(r.insetBy(dx: 0.75, dy: 0.75)))
        c.ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22)); c.ctx.setLineWidth(1.5); c.ctx.strokePath()
        c.text(label, r.midX - c.textW(label, 28, .medium)/2, 540 + 30, 28, .medium, NSColor(white: 1, alpha: 0.92))
    }
    c.save("banner.png")
}

// ===========================================================================
// 2. PRECISION — eyeballed vs measured
// ===========================================================================
do {
    let c = Canvas(2400, 1120)
    c.sheet(0, 2400)
    c.text("The difference between almost-native and native", 140, 90, 54, .bold, ink)
    c.text("Both look like a macOS switch. Only one matches the shipping control.",
           140, 168, 30, .regular, ink.withAlphaComponent(0.55))

    c.ctx.setStrokeColor(ink.withAlphaComponent(0.10).cgColor); c.ctx.setLineWidth(2)
    c.ctx.move(to: CGPoint(x: 1200, y: c.y(280))); c.ctx.addLine(to: CGPoint(x: 1200, y: c.y(600)))
    c.ctx.strokePath()

    c.text("EYEBALLED FROM A SCREENSHOT", 140, 300, 24, .bold, warn)
    let s: CGFloat = 6.0
    let gW = 51 * s, gH = 31 * s
    let gr = CGRect(x: 140, y: c.y(400, gH), width: gW, height: gH)
    c.ctx.addPath(capsulePath(gr))
    c.ctx.setFillColor(CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1))
    c.ctx.fillPath()
    let gk = CGRect(x: gr.maxX - 27*s - 2*s, y: gr.midY - 27*s/2, width: 27*s, height: 27*s)
    c.ctx.saveGState()
    c.ctx.setShadow(offset: CGSize(width: 0, height: -3*s), blur: 8*s, color: CGColor(gray: 0, alpha: 0.18))
    c.ctx.addPath(CGPath(ellipseIn: gk, transform: nil)); c.ctx.setFillColor(.white); c.ctx.fillPath()
    c.ctx.restoreGState()
    c.hDim(gr.minX, gr.maxX, 366, warn)
    c.text("51 × 31 pt", gr.midX - c.textW("51 × 31 pt", 28, .medium)/2, 318, 28, .medium, warn)
    c.vDim(gr.maxX + 40, 400, 400 + gH, warn)
    c.text("circular knob 27", gr.maxX + 62, 400 + gH/2 - 20, 27, .medium, warn)

    c.text("MEASURED FROM THE macOS 27 UI KIT", 1300, 300, 24, .bold, blue)
    let mTop = 400 + (gH - 24*s)/2
    let mr = c.kitSwitch(1300, mTop, s)
    c.hDim(mr.minX, mr.maxX, 366, blue)
    c.text("54 × 24 pt", mr.midX - c.textW("54 × 24 pt", 28, .medium)/2, 318, 28, .medium, blue)
    c.vDim(mr.maxX + 40, mTop, mTop + 24*s, blue)
    c.text("pill knob 32 × 20", mr.maxX + 62, mTop + 12*s - 20, 27, .medium, blue)

    let dy: CGFloat = 700
    c.text("What the eye missed", 140, dy, 34, .bold, ink)
    let rows = [
        ("track height", "31 pt", "24 pt", "-23%"),
        ("knob shape", "circle 27", "pill 32 x 20", "different geometry"),
        ("track aspect", "1.65 : 1", "2.25 : 1", "+36% wider"),
        ("knob travel", "20 pt", "18 pt", "-10%")
    ]
    let colX: [CGFloat] = [140, 640, 1000, 1420]
    c.text("property", colX[0], dy + 62, 24, .semibold, ink.withAlphaComponent(0.4))
    c.text("eyeballed", colX[1], dy + 62, 24, .semibold, warn.withAlphaComponent(0.8))
    c.text("kit value", colX[2], dy + 62, 24, .semibold, blue)
    c.text("error", colX[3], dy + 62, 24, .semibold, ink.withAlphaComponent(0.4))
    for (i, r) in rows.enumerated() {
        let ry = dy + 112 + CGFloat(i) * 56
        c.ctx.setStrokeColor(ink.withAlphaComponent(0.07).cgColor); c.ctx.setLineWidth(1)
        c.ctx.move(to: CGPoint(x: 140, y: c.y(ry - 12))); c.ctx.addLine(to: CGPoint(x: 2260, y: c.y(ry - 12)))
        c.ctx.strokePath()
        c.text(r.0, colX[0], ry, 27, .regular, ink.withAlphaComponent(0.75))
        c.text(r.1, colX[1], ry, 27, .regular, warn.withAlphaComponent(0.85), mono: true)
        c.text(r.2, colX[2], ry, 27, .semibold, blue, mono: true)
        c.text(r.3, colX[3], ry, 27, .regular, ink.withAlphaComponent(0.5), mono: true)
    }
    c.text("figma-apple-kit-extract reads these values out of the library instead of guessing them.",
           140, dy + 356, 27, .medium, ink.withAlphaComponent(0.55))
    c.save("precision.png")
}

// ===========================================================================
// 3. LAYERS — the Button's four-fill glass stack, exploded
// ===========================================================================
do {
    let c = Canvas(2400, 1000)
    c.navy()
    c.bloom(1900, 700, 900, NSColor(red: 0.25, green: 0.6, blue: 1.0, alpha: 1), 0.16)
    c.text("One control. Four fills.", 140, 96, 54, .bold, .white)
    c.text("Averaging the macOS 27 Button into a single colour loses the glass. The kit stacks them.",
           140, 174, 29, .regular, NSColor(white: 1, alpha: 0.55))

    let layers: [(String, CGColor)] = [
        ("black   @ 25%   base density", CGColor(gray: 0, alpha: 0.25)),
        ("white   @ 25%   lift",         CGColor(gray: 1, alpha: 0.25)),
        ("#444444 @ 60%   glass plate",  CGColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 0.60)),
        ("#F8F8F8 @ 20%   specular",     CGColor(red: 0.973, green: 0.973, blue: 0.973, alpha: 0.20))
    ]
    let lw: CGFloat = 420, lh: CGFloat = 150
    for (i, l) in layers.enumerated() {
        let ox = 200 + CGFloat(i) * 120
        let oy = 700 - CGFloat(i) * 130
        let r = CGRect(x: ox, y: c.y(oy, lh), width: lw, height: lh)
        c.ctx.saveGState()
        c.ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: CGColor(gray: 0, alpha: 0.42))
        c.ctx.addPath(capsulePath(r)); c.ctx.setFillColor(l.1); c.ctx.fillPath()
        c.ctx.restoreGState()
        c.ctx.addPath(capsulePath(r.insetBy(dx: 0.75, dy: 0.75)))
        c.ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.20)); c.ctx.setLineWidth(1.5); c.ctx.strokePath()
        c.ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22)); c.ctx.setLineWidth(1.5)
        c.ctx.move(to: CGPoint(x: r.maxX + 12, y: r.midY))
        c.ctx.addLine(to: CGPoint(x: 1180, y: r.midY)); c.ctx.strokePath()
        c.text(l.0, 1200, oy + lh/2 - 16, 25, .medium, NSColor(white: 1, alpha: 0.78), mono: true)
    }
    c.text("+ shadow  r15 . y8 . a0.02", 1200, 830, 25, .medium, NSColor(white: 1, alpha: 0.42), mono: true)

    let backdrop = CGRect(x: 1760, y: c.y(360, 300), width: 520, height: 300)
    c.ctx.saveGState(); c.ctx.addPath(rounded(backdrop, 40)); c.ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [
        figmaColors[3].withAlphaComponent(0.85).cgColor,
        figmaColors[2].withAlphaComponent(0.85).cgColor] as CFArray, locations: [0,1])!
    c.ctx.drawLinearGradient(bg, start: CGPoint(x: backdrop.minX, y: backdrop.maxY),
                             end: CGPoint(x: backdrop.maxX, y: backdrop.minY), options: [])
    c.ctx.restoreGState()
    let res = CGRect(x: 1830, y: c.y(440, 150), width: 380, height: 150)
    c.ctx.saveGState()
    c.ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 15, color: CGColor(gray: 0, alpha: 0.30))
    c.ctx.addPath(capsulePath(res)); c.ctx.setFillColor(CGColor(gray: 0, alpha: 0.25)); c.ctx.fillPath()
    c.ctx.restoreGState()
    for f in [CGColor(gray: 1, alpha: 0.25),
              CGColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 0.60),
              CGColor(red: 0.973, green: 0.973, blue: 0.973, alpha: 0.20)] {
        c.ctx.addPath(capsulePath(res)); c.ctx.setFillColor(f); c.ctx.fillPath()
    }
    c.ctx.addPath(capsulePath(res.insetBy(dx: 1, dy: 1)))
    c.ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.45)); c.ctx.setLineWidth(2); c.ctx.strokePath()
    c.text("composited over a background", backdrop.midX - c.textW("composited over a background", 26, .medium)/2, 700, 26, .medium, NSColor(white: 1, alpha: 0.62))
    c.save("layers.png")
}

// ===========================================================================
// PRECISION SERIES - reduction, negative space, obsessive measurement.
// Light, quiet, one idea per image. All geometry from the macOS 27 kit.
// ===========================================================================

let paper = CGColor(red: 0.961, green: 0.961, blue: 0.968, alpha: 1)   // F5F5F7
let hair  = NSColor(red: 0.06, green: 0.09, blue: 0.14, alpha: 1)

extension Canvas {
    func warmWhite() {
        ctx.setFillColor(paper); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    }
    func caption(_ title: String, _ sub: String, _ x: CGFloat = 150, _ top: CGFloat = 110) {
        text(title, x, top, 46, .semibold, hair)
        text(sub, x, top + 74, 27, .regular, hair.withAlphaComponent(0.45))
    }
    func footnote(_ s: String, _ x: CGFloat, _ top: CGFloat) {
        text(s, x, top, 23, .regular, hair.withAlphaComponent(0.38), mono: true)
    }
    func leader(_ x1: CGFloat, _ top: CGFloat, _ x2: CGFloat) {
        ctx.setStrokeColor(hair.withAlphaComponent(0.22).cgColor); ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: x1, y: y(top))); ctx.addLine(to: CGPoint(x: x2, y: y(top)))
        ctx.strokePath()
    }
    func disc(_ cx: CGFloat, _ top: CGFloat, _ d: CGFloat, _ col: NSColor) {
        let r = CGRect(x: cx - d/2, y: y(top, d), width: d, height: d)
        ctx.addPath(CGPath(ellipseIn: r, transform: nil)); ctx.setFillColor(col.cgColor); ctx.fillPath()
    }
    /// Superellipse — the continuous curvature Apple uses, not a circular arc.
    func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
        let p = CGMutablePath()
        let a = r.width/2, b = r.height/2, cx = r.midX, cy = r.midY
        let steps = 240
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let ct = cos(t), st = sin(t)
            let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2/n)
            let yy = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2/n)
            i == 0 ? p.move(to: CGPoint(x: x, y: yy)) : p.addLine(to: CGPoint(x: x, y: yy))
        }
        p.closeSubpath()
        return p
    }
}

// --- 4. ANATOMY — a window, taken apart ------------------------------------
do {
    let c = Canvas(2400, 1560)
    c.warmWhite()
    c.caption("A window, taken apart",
              "Five surfaces. The kit specifies each one separately — so does the code.")

    let wW: CGFloat = 860, wH: CGFloat = 300
    let layers: [(String, String, (CGRect) -> Void)] = [
        ("Traffic lights", "3 × 12 pt · 8 pt gap", { r in
            for (i, col) in [NSColor(red: 1, green: 0.373, blue: 0.341, alpha: 1),
                             NSColor(red: 1, green: 0.737, blue: 0.180, alpha: 1),
                             NSColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1)].enumerated() {
                let d: CGFloat = 34
                let e = CGRect(x: r.minX + 44 + CGFloat(i) * 52, y: r.midY - d/2, width: d, height: d)
                c.ctx.addPath(CGPath(ellipseIn: e, transform: nil))
                c.ctx.setFillColor(col.cgColor); c.ctx.fillPath()
            }
        }),
        ("Toolbar", "translucent · scroll-edge aware", { r in
            c.ctx.addPath(rounded(r, 26)); c.ctx.setFillColor(CGColor(gray: 1, alpha: 0.96)); c.ctx.fillPath()
            c.ctx.addPath(rounded(r, 26)); c.ctx.setStrokeColor(hair.withAlphaComponent(0.10).cgColor)
            c.ctx.setLineWidth(1.5); c.ctx.strokePath()
            for i in 0..<3 {
                let b = CGRect(x: r.minX + 300 + CGFloat(i) * 110, y: r.midY - 28, width: 84, height: 56)
                c.ctx.addPath(capsulePath(b)); c.ctx.setFillColor(hair.withAlphaComponent(0.06).cgColor)
                c.ctx.fillPath()
            }
        }),
        ("Sidebar", "vibrancy · behind-window", { r in
            c.ctx.addPath(rounded(r, 26)); c.ctx.setFillColor(CGColor(gray: 1, alpha: 0.9)); c.ctx.fillPath()
            let sb = CGRect(x: r.minX, y: r.minY, width: 250, height: r.height)
            c.ctx.saveGState(); c.ctx.addPath(rounded(r, 26)); c.ctx.clip()
            c.ctx.setFillColor(NSColor(red: 0.42, green: 0.52, blue: 0.68, alpha: 0.14).cgColor)
            c.ctx.fill(sb); c.ctx.restoreGState()
            for i in 0..<4 {
                let row = CGRect(x: r.minX + 26, y: r.maxY - 70 - CGFloat(i) * 54, width: 190, height: 30)
                c.ctx.addPath(capsulePath(row))
                c.ctx.setFillColor(hair.withAlphaComponent(i == 1 ? 0.16 : 0.07).cgColor); c.ctx.fillPath()
            }
        }),
        ("Content", "the only layer you write", { r in
            c.ctx.addPath(rounded(r, 26)); c.ctx.setFillColor(CGColor(gray: 1, alpha: 1)); c.ctx.fillPath()
            for i in 0..<3 {
                let row = CGRect(x: r.minX + 300, y: r.maxY - 80 - CGFloat(i) * 58,
                                 width: 420 - CGFloat(i) * 90, height: 22)
                c.ctx.addPath(capsulePath(row))
                c.ctx.setFillColor(hair.withAlphaComponent(0.09).cgColor); c.ctx.fillPath()
            }
        }),
        ("Shadow", "r15 · y8 · α0.02 — almost nothing", { r in
            c.ctx.saveGState()
            c.ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(gray: 0, alpha: 0.16))
            c.ctx.addPath(rounded(r, 26)); c.ctx.setFillColor(CGColor(gray: 0.92, alpha: 1)); c.ctx.fillPath()
            c.ctx.restoreGState()
        })
    ]

    for (i, l) in layers.enumerated() {
        let top = 330 + CGFloat(i) * 215
        let r = CGRect(x: 190 + CGFloat(i) * 26, y: c.y(top, wH), width: wW, height: wH)
        l.2(r)
        c.leader(r.maxX + 20, top + wH/2, 1420)
        c.text(l.0, 1450, top + wH/2 - 34, 30, .semibold, hair)
        c.footnote(l.1, 1450, top + wH/2 + 6)
    }
    c.save("anatomy.png")
}

// --- 5. LIGHTS — three circles ---------------------------------------------
do {
    let c = Canvas(2400, 1100)
    c.warmWhite()
    c.caption("Three circles", "Twelve points across. The most-used control on the system.")

    let cols: [(NSColor, String, String)] = [
        (NSColor(red: 1, green: 0.373, blue: 0.341, alpha: 1), "#FF5F57", "close"),
        (NSColor(red: 1, green: 0.737, blue: 0.180, alpha: 1), "#FEBC2E", "minimise"),
        (NSColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1), "#28C840", "zoom")
    ]
    let d: CGFloat = 300
    for (i, col) in cols.enumerated() {
        let cx = 560 + CGFloat(i) * 640
        c.disc(cx, 400, d, col.0)
        c.text(col.1, cx - c.textW(col.1, 30, .medium, mono: true)/2, 760, 30, .medium,
               hair.withAlphaComponent(0.7), mono: true)
        c.text(col.2, cx - c.textW(col.2, 26, .regular)/2, 812, 26, .regular, hair.withAlphaComponent(0.38))
    }
    // the 8pt gap, measured
    c.hDim(560 + d/2, 560 + 640 - d/2, 550, blue)
    c.text("8 pt", 560 + 320 - c.textW("8 pt", 24, .medium)/2, 502, 24, .medium, blue)
    c.footnote("diameter 12 pt · centres 20 pt apart · shown at 25×", 150, 980)
    c.save("lights.png")
}

// --- 6. RADII — continuous curvature ---------------------------------------
do {
    let c = Canvas(2400, 1200)
    c.warmWhite()
    c.caption("The corner is not an arc",
              "Apple's corners are superellipses. A circular arc meets the edge with a visible seam.")

    // concentric radii, left
    let sizes: [(CGFloat, String)] = [(560, "34 pt  panel"), (420, "24 pt  pill"),
                                      (300, "18 pt  tile"), (180, "10 pt  control")]
    for (i, s) in sizes.enumerated() {
        let r = CGRect(x: 430 - s.0/2, y: c.y(700 - s.0/2, s.0), width: s.0, height: s.0)
        c.ctx.addPath(rounded(r, s.0 * 0.20))
        c.ctx.setStrokeColor(hair.withAlphaComponent(0.16 + CGFloat(i) * 0.12).cgColor)
        c.ctx.setLineWidth(2); c.ctx.strokePath()
    }
    for (i, s) in sizes.enumerated() {
        c.footnote(s.1, 820, 560 + CGFloat(i) * 46)
    }
    c.footnote("concentric — inner radius = outer − inset", 820, 776)

    // arc vs superellipse, right
    let box = CGRect(x: 1560, y: c.y(470, 460), width: 460, height: 460)
    c.ctx.addPath(rounded(box, 130))
    c.ctx.setStrokeColor(NSColor(red: 0.85, green: 0.24, blue: 0.20, alpha: 0.75).cgColor)
    c.ctx.setLineWidth(4); c.ctx.strokePath()
    c.ctx.addPath(c.squircle(box, n: 5))
    c.ctx.setStrokeColor(blue.cgColor); c.ctx.setLineWidth(4); c.ctx.strokePath()
    c.text("circular arc", 2080, 500, 26, .medium, NSColor(red: 0.85, green: 0.24, blue: 0.20, alpha: 1))
    c.text("superellipse  n = 5", 2080, 546, 26, .medium, blue)
    c.footnote("the gap between them is the whole difference", 1560, 990)
    c.save("radii.png")
}

// --- 7. TYPE — the ramp -----------------------------------------------------
do {
    let c = Canvas(2400, 1250)
    c.warmWhite()
    c.caption("One typeface, five jobs", "SF Pro. The kit specifies size and weight per role — nothing else.")

    let ramp: [(CGFloat, NSFont.Weight, String, String)] = [
        (56, .bold,     "Battery",        "56 · bold      display"),
        (28, .semibold, "Predicted range","28 · semibold  title"),
        (20, .medium,   "2 h 14 m remaining", "20 · medium    body"),
        (15, .regular,  "Updated a moment ago", "15 · regular   secondary"),
        (11, .semibold, "R A M   F R E E", "11 · semibold  label")
    ]
    for (i, r) in ramp.enumerated() {
        let top = 300 + CGFloat(i) * 150
        c.text(r.2, 150, top, r.0, r.1, hair)
        c.leader(1100, top + r.0 * 0.5, 1500)
        c.footnote(r.3, 1530, top + r.0 * 0.5 - 14)
    }
    c.footnote("no custom faces · no letterspacing · optical sizes handled by the system", 150, 1110)
    c.save("type.png")
}

// --- 8. MATERIALS — the same control, four backdrops ------------------------
do {
    let c = Canvas(2400, 1000)
    c.warmWhite()
    c.caption("The control does not have a colour",
              "One translucent stack, four backgrounds. This is what flattening to a hex value destroys.")

    let strip = CGRect(x: 150, y: c.y(340, 420), width: 2100, height: 420)
    c.ctx.saveGState(); c.ctx.addPath(rounded(strip, 40)); c.ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1),
        figmaColors[2].cgColor,
        figmaColors[3].cgColor,
        CGColor(gray: 0.97, alpha: 1)] as CFArray, locations: [0, 0.34, 0.66, 1])!
    c.ctx.drawLinearGradient(g, start: CGPoint(x: strip.minX, y: 0),
                             end: CGPoint(x: strip.maxX, y: 0), options: [])
    c.ctx.restoreGState()

    for i in 0..<4 {
        let r = CGRect(x: strip.minX + 130 + CGFloat(i) * 500, y: strip.midY - 75, width: 360, height: 150)
        c.ctx.saveGState()
        c.ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 15, color: CGColor(gray: 0, alpha: 0.10))
        c.ctx.addPath(capsulePath(r)); c.ctx.setFillColor(CGColor(gray: 0, alpha: 0.25)); c.ctx.fillPath()
        c.ctx.restoreGState()
        for f in [CGColor(gray: 1, alpha: 0.25),
                  CGColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 0.60),
                  CGColor(red: 0.973, green: 0.973, blue: 0.973, alpha: 0.20)] {
            c.ctx.addPath(capsulePath(r)); c.ctx.setFillColor(f); c.ctx.fillPath()
        }
        c.ctx.addPath(capsulePath(r.insetBy(dx: 1, dy: 1)))
        c.ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.40)); c.ctx.setLineWidth(2); c.ctx.strokePath()
    }
    c.footnote("identical fills · identical opacities · four different results", 150, 830)
    c.save("materials.png")
}

// --- 9. INVENTORY — the parts, at kit metrics -------------------------------
do {
    let c = Canvas(2400, 1130)
    c.warmWhite()
    c.caption("The parts", "Every control drawn from library values. Nothing here was traced from a screenshot.")

    func cell(_ col: Int, _ row: Int) -> CGPoint {
        CGPoint(x: 190 + CGFloat(col) * 545, y: 380 + CGFloat(row) * 330)
    }
    func label(_ col: Int, _ row: Int, _ name: String, _ spec: String) {
        let p = cell(col, row)
        c.text(name, p.x, p.y + 140, 26, .semibold, hair.withAlphaComponent(0.8))
        c.footnote(spec, p.x, p.y + 178)
    }

    // switch on / off
    var p = cell(0, 0); c.kitSwitch(p.x, p.y, 3.4);        label(0, 0, "Switch — on",  "54 × 24 · knob 32 × 20")
    p = cell(1, 0); c.kitSwitch(p.x, p.y, 3.4, on: false); label(1, 0, "Switch — off", "track black @ 85%")

    // capsule button
    p = cell(2, 0)
    var r = CGRect(x: p.x, y: c.y(p.y, 82), width: 230, height: 82)
    c.ctx.addPath(capsulePath(r)); c.ctx.setFillColor(hair.withAlphaComponent(0.08).cgColor); c.ctx.fillPath()
    c.ctx.addPath(capsulePath(r)); c.ctx.setStrokeColor(hair.withAlphaComponent(0.14).cgColor)
    c.ctx.setLineWidth(1.5); c.ctx.strokePath()
    c.text("Continue", r.midX - c.textW("Continue", 27, .medium)/2, p.y + 26, 27, .medium, hair)
    label(2, 0, "Button", "cornerRadius 1000")

    // segmented
    p = cell(3, 0)
    r = CGRect(x: p.x, y: c.y(p.y, 82), width: 330, height: 82)
    c.ctx.addPath(capsulePath(r)); c.ctx.setFillColor(hair.withAlphaComponent(0.07).cgColor); c.ctx.fillPath()
    let seg = CGRect(x: r.minX + 5, y: r.minY + 5, width: 106, height: 72)
    c.ctx.addPath(capsulePath(seg)); c.ctx.setFillColor(CGColor(gray: 1, alpha: 1)); c.ctx.fillPath()
    for (i, s) in ["Day", "Week", "Year"].enumerated() {
        let sx = r.minX + 5 + CGFloat(i) * 108 + 53
        c.text(s, sx - c.textW(s, 24, .medium)/2, p.y + 28, 24, .medium,
               hair.withAlphaComponent(i == 0 ? 0.9 : 0.5))
    }
    label(3, 0, "Segmented", "equal widths · pill selection")

    // checkbox + radio
    p = cell(0, 1)
    r = CGRect(x: p.x, y: c.y(p.y, 62), width: 62, height: 62)
    c.ctx.addPath(rounded(r, 16)); c.ctx.setFillColor(blue.cgColor); c.ctx.fillPath()
    c.ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); c.ctx.setLineWidth(7); c.ctx.setLineCap(.round)
    c.ctx.move(to: CGPoint(x: r.minX + 17, y: r.midY + 2))
    c.ctx.addLine(to: CGPoint(x: r.midX - 3, y: r.minY + 18))
    c.ctx.addLine(to: CGPoint(x: r.maxX - 15, y: r.maxY - 18)); c.ctx.strokePath()
    c.ctx.setLineCap(.butt)
    label(0, 1, "Checkbox", "62 · r16 · SF checkmark")

    p = cell(1, 1)
    c.disc(p.x + 31, p.y, 62, blue)
    c.disc(p.x + 31, p.y + 20, 22, NSColor.white)
    label(1, 1, "Radio", "concentric · dot ⌀22")

    // slider
    p = cell(2, 1)
    let track = CGRect(x: p.x, y: c.y(p.y + 24, 12), width: 340, height: 12)
    c.ctx.addPath(capsulePath(track)); c.ctx.setFillColor(hair.withAlphaComponent(0.12).cgColor); c.ctx.fillPath()
    let fill = CGRect(x: track.minX, y: track.minY, width: 210, height: 12)
    c.ctx.addPath(capsulePath(fill)); c.ctx.setFillColor(blue.cgColor); c.ctx.fillPath()
    c.ctx.saveGState()
    c.ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: CGColor(gray: 0, alpha: 0.20))
    c.disc(track.minX + 210, p.y + 8, 44, .white)
    c.ctx.restoreGState()
    label(2, 1, "Slider", "thumb ⌀44 · track 12")

    // progress
    p = cell(3, 1)
    let pt = CGRect(x: p.x, y: c.y(p.y + 24, 12), width: 340, height: 12)
    c.ctx.addPath(capsulePath(pt)); c.ctx.setFillColor(hair.withAlphaComponent(0.12).cgColor); c.ctx.fillPath()
    let pf = CGRect(x: pt.minX, y: pt.minY, width: 240, height: 12)
    c.ctx.addPath(capsulePath(pf)); c.ctx.setFillColor(NSColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1).cgColor)
    c.ctx.fillPath()
    label(3, 1, "Progress", "determinate · 12 pt")

    c.footnote("apple-design-toolkit · every value read from the macOS 27 UI Kit", 190, 1020)
    c.save("inventory.png")
}

// ===========================================================================
// SOCIAL — 1080 x 1080. Real Liquid Glass: the backdrop is rendered offscreen,
// blurred with CoreImage, and shown through the panel. (Snapshotting the live
// rep instead orphans the active context and silently drops all later drawing.)
// ===========================================================================

func offscreen(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return r.cgImage!
}

func blurCG(_ cg: CGImage, _ radius: Double) -> CGImage? {
    let ci = CIImage(cgImage: cg)
    guard let f = CIFilter(name: "CIGaussianBlur") else { return nil }
    f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
    f.setValue(radius, forKey: kCIInputRadiusKey)
    guard let out = f.outputImage?.cropped(to: ci.extent) else { return nil }
    return CIContext(options: nil).createCGImage(out, from: ci.extent)
}

func rawBloom(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor, _ a: CGFloat) {
    let cc = c.withAlphaComponent(a).cgColor
    let g = CGGradient(colorsSpace: space, colors: [cc, cc.copy(alpha: 0)!] as CFArray, locations: [0,1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                           endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}

extension Canvas {
    func glassWith(_ r: CGRect, _ rad: CGFloat, _ blurred: CGImage?, tint: CGFloat = 0.10) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(rounded(r, rad)); ctx.setFillColor(CGColor(gray: 0.02, alpha: 0.55)); ctx.fillPath()
        ctx.restoreGState()

        if let b = blurred {
            ctx.saveGState()
            ctx.addPath(rounded(r, rad)); ctx.clip()
            ctx.draw(b, in: CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setFillColor(CGColor(gray: 1, alpha: tint)); ctx.fill(r)
            let sheen = CGGradient(colorsSpace: space, colors: [
                CGColor(gray: 1, alpha: 0.28), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0,1])!
            ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: r.maxY),
                                   end: CGPoint(x: 0, y: r.maxY - r.height * 0.44), options: [])
            let under = CGGradient(colorsSpace: space, colors: [
                CGColor(gray: 1, alpha: 0.14), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0,1])!
            ctx.drawLinearGradient(under, start: CGPoint(x: 0, y: r.minY),
                                   end: CGPoint(x: 0, y: r.minY + r.height * 0.24), options: [])
            ctx.restoreGState()
        }
        ctx.addPath(rounded(r.insetBy(dx: 1.5, dy: 1.5), rad))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.50)); ctx.setLineWidth(3); ctx.strokePath()
    }

    func centred(_ s: String, _ top: CGFloat, _ size: CGFloat, _ w: NSFont.Weight,
                 _ col: NSColor, mono: Bool = false) {
        text(s, (W - textW(s, size, w, mono: mono)) / 2, top, size, w, col, mono: mono)
    }

    /// Folded-paper pulse mark — same miter-offset + per-facet normal shading
    /// used for the app icon.
    func pulseMark(_ box: CGRect) {
        let src: [[CGFloat]] = [[230,553],[352,553],[412,468],[464,608],[530,272],
                                [600,748],[660,498],[722,553],[795,553]]
        let sx = box.width / 570, sy = box.height / 480
        let P = src.map { CGPoint(x: box.minX + ($0[0] - 225) * sx,
                                  y: box.maxY - ($0[1] - 262) * sy) }
        let h = 28 * min(sx, sy)
        func nrm(_ v: CGPoint) -> CGPoint { let l = max(hypot(v.x, v.y), 0.0001); return CGPoint(x: v.x/l, y: v.y/l) }
        var Noff: [CGPoint] = [], Nlit: [CGPoint] = []
        for i in 0..<(P.count - 1) {
            let d = nrm(CGPoint(x: P[i+1].x - P[i].x, y: P[i+1].y - P[i].y))
            Noff.append(CGPoint(x: -d.y, y: d.x)); Nlit.append(CGPoint(x: d.y, y: -d.x))
        }
        var top: [CGPoint] = [], bot: [CGPoint] = []
        for i in 0..<P.count {
            var m: CGPoint, s: CGFloat
            if i == 0 { m = Noff[0]; s = h }
            else if i == P.count - 1 { m = Noff[Noff.count - 1]; s = h }
            else {
                m = nrm(CGPoint(x: Noff[i-1].x + Noff[i].x, y: Noff[i-1].y + Noff[i].y))
                let cc = m.x * Noff[i-1].x + m.y * Noff[i-1].y
                s = abs(cc) < 0.35 ? h * 2.4 : min(h / cc, h * 2.4)
            }
            top.append(CGPoint(x: P[i].x + m.x * s, y: P[i].y + m.y * s))
            bot.append(CGPoint(x: P[i].x - m.x * s, y: P[i].y - m.y * s))
        }
        let out = CGMutablePath()
        out.move(to: CGPoint(x: top[0].x + 5, y: top[0].y - 7))
        for p in top.dropFirst() { out.addLine(to: CGPoint(x: p.x + 5, y: p.y - 7)) }
        for p in bot.reversed() { out.addLine(to: CGPoint(x: p.x + 5, y: p.y - 7)) }
        out.closeSubpath()
        ctx.addPath(out); ctx.setFillColor(CGColor(red: 0.02, green: 0.06, blue: 0.16, alpha: 1)); ctx.fillPath()

        let L = nrm(CGPoint(x: -0.55, y: 0.83))
        let stops: [(CGFloat, [CGFloat])] = [(0,[26,86,170]),(0.34,[41,128,235]),(0.66,[125,205,255]),(1,[255,255,255])]
        for i in 0..<(P.count - 1) {
            let t = ((Nlit[i].x * L.x + Nlit[i].y * L.y) + 1) / 2
            var col: [CGFloat] = [255,255,255]
            for k in 0..<(stops.count - 1) where t <= stops[k+1].0 || k == stops.count - 2 {
                let f = max(0, min(1, (t - stops[k].0) / (stops[k+1].0 - stops[k].0)))
                col = (0..<3).map { stops[k].1[$0] + (stops[k+1].1[$0] - stops[k].1[$0]) * f }
                break
            }
            let q = CGMutablePath()
            q.move(to: top[i]); q.addLine(to: top[i+1]); q.addLine(to: bot[i+1]); q.addLine(to: bot[i])
            q.closeSubpath()
            ctx.addPath(q)
            ctx.setFillColor(CGColor(red: col[0]/255, green: col[1]/255, blue: col[2]/255, alpha: 1))
            ctx.fillPath()
        }
        for i in 1..<(P.count - 1) { ctx.move(to: top[i]); ctx.addLine(to: bot[i]) }
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.24)); ctx.setLineWidth(2); ctx.strokePath()
    }
}

// --- SOCIAL 1: MacPulse -----------------------------------------------------
do {
    let full = CGRect(x: 0, y: 0, width: 1080, height: 1080)
    let sharp = offscreen(1080, 1080) { ctx in
        let g = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.086, green: 0.153, blue: 0.286, alpha: 1),
            CGColor(red: 0.012, green: 0.031, blue: 0.078, alpha: 1)] as CFArray, locations: [0,1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 1080), end: CGPoint(x: 760, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        rawBloom(ctx, 190, 880, 620, NSColor(red: 0.22, green: 0.58, blue: 1.0, alpha: 1), 0.44)
        rawBloom(ctx, 940, 320, 560, NSColor(red: 0.35, green: 0.84, blue: 1.0, alpha: 1), 0.28)
        rawBloom(ctx, 620, 990, 520, NSColor(red: 0.58, green: 0.36, blue: 1.0, alpha: 1), 0.24)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.12)); ctx.setLineWidth(6)
        let wave: [[CGFloat]] = [[-40,660],[190,660],[262,576],[314,724],[418,250],[506,910],[578,556],[664,660],[1120,660]]
        for (i, p) in wave.enumerated() {
            i == 0 ? ctx.move(to: CGPoint(x: p[0], y: 1080 - p[1]))
                   : ctx.addLine(to: CGPoint(x: p[0], y: 1080 - p[1]))
        }
        ctx.strokePath()
    }
    let blur = blurCG(sharp, 24)

    let c = Canvas(1080, 1080)
    c.ctx.draw(sharp, in: full)
    c.pulseMark(CGRect(x: 396, y: c.y(78, 236), width: 288, height: 236))

    let panel = CGRect(x: 88, y: c.y(400, 268), width: 904, height: 268)
    c.glassWith(panel, 54, blur, tint: 0.10)
    c.text("≥ 2:14", 140, 452, 110, .bold, .white)
    c.text("95% confidence runtime", 148, 582, 27, .medium, NSColor(white: 1, alpha: 0.66))
    c.kitSwitch(716, 470, 3.3)
    c.text("Low Power", 716, 566, 25, .medium, NSColor(white: 1, alpha: 0.6))

    c.centred("MacPulse", 726, 86, .bold, .white)
    c.centred("Your Mac saves power based on a number that cannot", 846, 27, .regular, NSColor(white: 1, alpha: 0.62))
    c.centred("know the answer. This one forecasts instead.", 884, 27, .regular, NSColor(white: 1, alpha: 0.62))
    c.centred("github.com/infinitule/MacPulse", 980, 24, .medium, NSColor(white: 1, alpha: 0.38), mono: true)
    c.save("social-macpulse.png")
}

// --- SOCIAL 2: Apple Design Toolkit -----------------------------------------
do {
    let full = CGRect(x: 0, y: 0, width: 1080, height: 1080)
    let sharp = offscreen(1080, 1080) { ctx in
        let g = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.055, green: 0.078, blue: 0.153, alpha: 1),
            CGColor(red: 0.008, green: 0.020, blue: 0.047, alpha: 1)] as CFArray, locations: [0,1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 1080), end: CGPoint(x: 820, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        rawBloom(ctx, 140, 940, 540, figmaColors[0], 0.55)
        rawBloom(ctx, 430, 1020, 470, figmaColors[1], 0.45)
        rawBloom(ctx, 790, 910, 540, figmaColors[2], 0.52)
        rawBloom(ctx, 990, 540, 500, figmaColors[3], 0.48)
        rawBloom(ctx, 610, 700, 430, figmaColors[4], 0.32)
    }
    let blur = blurCG(sharp, 32)

    let c = Canvas(1080, 1080)
    c.ctx.draw(sharp, in: full)
    c.centred("A P P L E   D E S I G N   T O O L K I T", 88, 25, .semibold, NSColor(white: 1, alpha: 0.55))

    let card = CGRect(x: 86, y: c.y(168, 428), width: 908, height: 428)
    c.glassWith(card, 62, blur, tint: 0.12)

    let ss: CGFloat = 6.4
    let sw = c.kitSwitch((1080 - 54 * ss) / 2, 300, ss)
    c.hDim(sw.minX, sw.maxX, 258, NSColor(white: 1, alpha: 0.8))
    c.centred("54 × 24 pt", 202, 30, .medium, NSColor(white: 1, alpha: 0.92))
    c.centred("knob 32 × 20 pill   ·   track black @ 85%", 492, 27, .medium, NSColor(white: 1, alpha: 0.72))
    c.centred("cornerRadius 1000   ·   shadow r15 · y8 · α0.02", 536, 25, .regular, NSColor(white: 1, alpha: 0.46))

    c.centred("Read Apple's design system.", 700, 52, .bold, .white)
    c.centred("Ship it as native code.", 762, 52, .bold, NSColor(white: 1, alpha: 0.58))
    c.centred("4 Claude Code skills  ·  measured from the macOS 27 UI Kit",
              872, 26, .regular, NSColor(white: 1, alpha: 0.58))
    c.centred("github.com/infinitule/apple-design-toolkit", 966, 24, .medium, NSColor(white: 1, alpha: 0.38), mono: true)
    c.save("social-toolkit.png")
}
