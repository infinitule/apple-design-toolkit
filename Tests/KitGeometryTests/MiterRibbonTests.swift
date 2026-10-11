import XCTest
@testable import KitGeometry

final class MiterRibbonTests: XCTestCase {
    func testStraightSegmentNormals() throws {
        let r = try MiterRibbon(polyline: [Vec2(0, 0), Vec2(10, 0)], halfWidth: 2)
        XCTAssertEqual(r.segmentNormals.count, 1)
        XCTAssertTrue(r.segmentNormals[0].isApprox(Vec2(0, 1))) // perpLeft of +x
        XCTAssertTrue(r.top[0].isApprox(Vec2(0, 2)))
        XCTAssertTrue(r.bottom[0].isApprox(Vec2(0, -2)))
        XCTAssertTrue(r.top[1].isApprox(Vec2(10, 2)))
        XCTAssertEqual(r.facets.count, 1)
        XCTAssertTrue(Polygon.isConvexQuad(r.facets[0]))
        XCTAssertTrue(r.clampedJoints.isEmpty)
    }

    func testRightAngleMiterLength() throws {
        // L shape: (0,0)->(10,0)->(10,10). At the corner, n1=(0,1), n2=(-1,0),
        // m = normalize((-1,1)), dot(m,n1)=1/sqrt(2), s = h*sqrt(2).
        let r = try MiterRibbon(polyline: [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10)], halfWidth: 1)
        XCTAssertEqual(r.clampedJoints, [])
        // m = normalize((-1,1)), s = h*sqrt(2) => offset = (-1, 1); top = (9, 1)
        XCTAssertEqual(r.top[1].x, 9, accuracy: 1e-9)
        XCTAssertEqual(r.top[1].y, 1, accuracy: 1e-9)
        XCTAssertEqual((r.top[1] - r.spine[1]).length, sqrt(2.0), accuracy: 1e-9)
    }

    func testSharpReversalIsClamped() throws {
        // Exact 180 degree turn: n1 + n2 = 0.
        let r = try MiterRibbon(polyline: [Vec2(0, 0), Vec2(10, 0), Vec2(0, 0)], halfWidth: 1)
        XCTAssertEqual(r.clampedJoints, [1])
        XCTAssertEqual(r.top[1].y, 2.4, accuracy: 1e-9) // limit = 2.4 * h
    }

    func testRejectsBadInput() {
        XCTAssertThrowsError(try MiterRibbon(polyline: [Vec2(0, 0)], halfWidth: 1))
        XCTAssertThrowsError(try MiterRibbon(polyline: [Vec2(0, 0), Vec2(1, 0)], halfWidth: 0))
        XCTAssertThrowsError(try MiterRibbon(polyline: [Vec2(0, 0), Vec2(.nan, 0)], halfWidth: 1))
    }

    func testDropsDuplicatePoints() throws {
        let r = try MiterRibbon(polyline: [Vec2(0, 0), Vec2(0, 0), Vec2(5, 0)], halfWidth: 1)
        XCTAssertEqual(r.spine.count, 2)
    }

    func testPulseMarkProducesValidFacets() throws {
        let fitted = PolylineFit.fit(PulseMark.source, into: Vec2(0, 0), size: Vec2(570, 480), flipY: true)
        let r = try MiterRibbon(polyline: fitted, halfWidth: PulseMark.halfWidth)
        XCTAssertEqual(r.facets.count, PulseMark.source.count - 1)
        for q in r.facets { XCTAssertTrue(Polygon.isConvexQuad(q), "facet folded: \(q)") }
        XCTAssertEqual(r.creases.count, PulseMark.source.count - 2)
        XCTAssertEqual(r.outline.count, r.top.count + r.bottom.count)
    }

    func testPulseMarkMatchesImagesSwiftHalfWidthScaling() throws {
        // images.swift: h = 28 * min(sx, sy) with sx = box.w/570, sy = box.h/480.
        let boxW = 285.0, boxH = 240.0
        let sx = boxW / 570, sy = boxH / 480
        let h = 28 * min(sx, sy)
        let fitted = PolylineFit.fit(PulseMark.source, into: Vec2(0, 0), size: Vec2(boxW, boxH), flipY: true)
        let r = try MiterRibbon(polyline: fitted, halfWidth: h)
        // End vertices offset exactly h along the segment normal.
        let endLift = (r.top[0] - r.spine[0]).length
        XCTAssertEqual(endLift, h, accuracy: 1e-9)
    }
}

final class FacetShadingTests: XCTestCase {
    func testRampEndpoints() throws {
        let ramp = ColorRamp.pulseBlue
        XCTAssertEqual(ramp.sample(0), [26, 86, 170])
        XCTAssertEqual(ramp.sample(1), [255, 255, 255])
        let mid = ramp.sample(0.34)
        XCTAssertEqual(mid[0], 41, accuracy: 1e-9)
    }

    func testImagesSwiftRuleDarkensFlatHorizontals() {
        let shader = FacetShader.imagesSwift
        let intensity = shader.intensity(direction: Vec2(1, 0))
        // perpRight of +x is (0,-1); light ≈ (-0.55, 0.83); dot is negative → t < 0.5
        XCTAssertLessThan(intensity, 0.5)
    }

    func testUpwardRuleBrightensFlatHorizontalsInYDown() {
        // Top-left light in y-down space points toward negative Y.
        let shader = FacetShader(light: Vec2(-0.55, -0.83), rule: .upward(.yDown))
        XCTAssertGreaterThan(shader.intensity(direction: Vec2(1, 0)), 0.5)
    }

    func testShadeCountMatchesSegments() throws {
        let r = try MiterRibbon(polyline: PulseMark.source, halfWidth: 1)
        XCTAssertEqual(FacetShader.imagesSwift.shade(r).count, r.segmentDirections.count)
    }
}

final class IconGridTests: XCTestCase {
    func testPlateContains() {
        let g = IconGrid()
        XCTAssertTrue(g.plateContains(Vec2(512, 512)))
        XCTAssertFalse(g.plateContains(Vec2(0, 0)))       // outside the plate
        XCTAssertFalse(g.plateContains(Vec2(100, 100)))   // corner of the bounding box, outside the squircle
        XCTAssertTrue(g.plateContains(Vec2(100 + 185, 100 + 185)))
    }

    func testMarkBoxCentred() {
        let g = IconGrid()
        let box = g.markBox
        XCTAssertEqual(box.size, 824 * 0.62, accuracy: 1e-9)
        XCTAssertEqual(box.origin.x, box.origin.y, accuracy: 1e-9)
    }

    func testSuperellipseImplicit() {
        let c = Vec2(0, 0)
        // On the axis of a unit circle (n=2): implicit = 1.
        XCTAssertEqual(Superellipse.implicit(Vec2(1, 0), center: c, a: 1, b: 1, n: 2), 1, accuracy: 1e-9)
        let pts = Superellipse.points(center: c, a: 1, b: 1, n: 5, count: 32)
        XCTAssertEqual(pts.count, 32)
        for p in pts {
            XCTAssertEqual(Superellipse.implicit(p, center: c, a: 1, b: 1, n: 5), 1, accuracy: 1e-6)
        }
    }
}
