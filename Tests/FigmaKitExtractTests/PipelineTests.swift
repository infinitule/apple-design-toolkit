import XCTest
@testable import FigmaKitExtract

final class CompactPipelineTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }

    func testCompactButtonAnatomy() throws {
        let node = try NodeParser().parse(JSONValue.parse(fixture("button-compact")))
        XCTAssertEqual(node.name, "Button")
        XCTAssertEqual(node.width, 120)
        XCTAssertEqual(node.height, 32)
        if case .uniform(let r) = node.radii { XCTAssertEqual(r, 1000) } else { XCTFail("expected uniform radius") }
        XCTAssertEqual(node.fills.count, 4)
        XCTAssertEqual(node.effects.count, 4)
        XCTAssertEqual(node.variantAxes["Mode"], ["Dark", "Light"])
        XCTAssertEqual(node.variantAxes["State"], ["Idle", "Clicked"])

        let tokens = try TokenExtractor().extract(node)
        XCTAssertEqual(tokens.count, 1)
        let t = tokens[0]
        XCTAssertEqual(t.shape, .capsule)
        XCTAssertEqual(t.fills.count, 4)
        XCTAssertTrue(t.hasGlassEffect)
        XCTAssertNotNil(t.specularEdges)
        XCTAssertEqual(t.specularEdges!.top.y, 40)
        XCTAssertEqual(t.specularEdges!.bottom.y, -40)
        XCTAssertTrue(t.notes.contains(where: { $0.contains("stacked translucent") }))
        XCTAssertTrue(t.notes.contains(where: { $0.contains("whisper-soft") }))
    }

    func testGeneratedSwiftCompilesAsSourceText() throws {
        let node = try NodeParser().parse(JSONValue.parse(fixture("button-compact")))
        let tokens = try TokenExtractor().extract(node)
        let src = SwiftUIGenerator(namespace: "Demo").generate(tokens)
        XCTAssertTrue(src.contains("public enum Demo"))
        XCTAssertTrue(src.contains("KitComponentSpec"))
        XCTAssertTrue(src.contains(".capsule"))
        XCTAssertTrue(src.contains("public struct KitRGBA"))
        // Identifier from "Button"
        XCTAssertTrue(src.contains("static let button:"))
        // Numbers trimmed
        XCTAssertTrue(src.contains("width: 120"))
        XCTAssertFalse(src.contains("120.0000"))
    }
}

final class RestPipelineTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }

    func testSwitchSetAndVariantSelect() throws {
        let node = try NodeParser().parse(JSONValue.parse(fixture("switch-rest")))
        XCTAssertEqual(node.type, "COMPONENT_SET")
        XCTAssertEqual(node.children.count, 4)
        XCTAssertEqual(node.variantAxes["Mode"]?.sorted(), ["Dark", "Light"])

        let matrix = VariantMatrix(names: node.children.map(\.name))
        XCTAssertEqual(matrix.missingCombinations.count, 0)
        let name = try matrix.select(required: ["Mode": "Dark", "State": "On"])
        XCTAssertEqual(name, "Mode=Dark, State=On")

        let token = try TokenExtractor().extract(node, selecting: ["Mode": "Dark", "State": "On"])
        XCTAssertEqual(token.width, 54)
        XCTAssertEqual(token.height, 24)
        XCTAssertEqual(token.shape, .capsule)
        XCTAssertEqual(token.variant["State"], "On")
        // Knob is a named part with the skill's 32x20 pill geometry.
        let knob = token.parts.first(where: { $0.name == "Knob" })
        XCTAssertEqual(knob?.width, 32)
        XCTAssertEqual(knob?.height, 20)
        XCTAssertEqual(knob?.shape, .capsule)
    }

    func testInvisibleEffectsDropped() throws {
        let json = """
        {"name":"X","type":"FRAME","width":1,"height":1,
         "effects":[{"type":"DROP_SHADOW","radius":1,"visible":false},
                    {"type":"DROP_SHADOW","radius":2,"visible":true}]}
        """
        let node = try NodeParser().parse(JSONValue.parse(Data(json.utf8)))
        XCTAssertEqual(node.effects.count, 1)
        XCTAssertEqual(node.effects[0].radius, 2)
    }

    func testPerCornerRadii() throws {
        let json = """
        {"name":"X","type":"FRAME","width":40,"height":40,
         "rectangleCornerRadii":[4,8,4,8]}
        """
        let node = try NodeParser().parse(JSONValue.parse(Data(json.utf8)))
        if case .perCorner(let v) = node.radii { XCTAssertEqual(v, [4, 8, 4, 8]) }
        else { XCTFail() }
    }

    func testNegativeSizeRejected() {
        let json = #"{"name":"X","type":"FRAME","width":-1,"height":2}"#
        XCTAssertThrowsError(try NodeParser().parse(JSONValue.parse(Data(json.utf8))))
    }
}

final class VariableAndSearchTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: XCTUnwrap(url))
    }

    func testAliasResolution() throws {
        let store = try VariableStore(json: JSONValue.parse(fixture("variables")))
        if case .color(let c) = try store.resolve("VariableID:alias", modeName: "Dark") {
            XCTAssertEqual(c.g, 0.78, accuracy: 1e-9)
        } else { XCTFail("expected colour") }
        if case .number(let n) = try store.resolve("VariableID:radius", modeName: "Light") {
            XCTAssertEqual(n, 1000)
        } else { XCTFail("expected number") }
        XCTAssertEqual(store.variable(named: "Toggle/Track-On")?.id, "VariableID:track")
    }

    func testCycleDetection() throws {
        let a = VariableStore.Variable(id: "a", name: "A", collectionId: "c",
                                       valuesByMode: ["m": .alias("b")])
        let b = VariableStore.Variable(id: "b", name: "B", collectionId: "c",
                                       valuesByMode: ["m": .alias("a")])
        let store = VariableStore(variables: [a, b],
                                  collections: [.init(id: "c", name: "C", defaultModeId: "m", modes: ["m": "Dark"])])
        XCTAssertThrowsError(try store.resolve("a")) { err in
            guard case VariableStore.ResolveError.cycle = err as! VariableStore.ResolveError else {
                return XCTFail("expected cycle, got \(err)")
            }
        }
    }

    func testSearchPlannerSplitsMultiWord() {
        let q = SearchPlanner.singleTermQueries("window panel material glass button")
        XCTAssertEqual(q, ["window", "panel", "material", "glass", "button"])
        // Singularisation + stop words
        XCTAssertEqual(SearchPlanner.singleTermQueries("the toggles and switches"), ["toggle", "switch"])
    }

    func testCoverOnlyDetection() {
        XCTAssertEqual(KitFileCheck.inspect(pages: ["Cover"]), .coverOnly)
        XCTAssertEqual(KitFileCheck.inspect(pages: ["Cover", "Components"]), .ok)
        XCTAssertEqual(KitFileCheck.inspect(pages: []), .empty)
    }

    func testVariantSelectErrors() {
        let m = VariantMatrix(names: ["Mode=Dark, State=Idle", "Mode=Light, State=Idle"])
        XCTAssertThrowsError(try m.select(required: ["Mode": "Sepia"]))
        XCTAssertThrowsError(try m.select(required: ["Size": "XL"]))
        XCTAssertEqual(m.missingCombinations.count, 0)
        let sparse = VariantMatrix(names: ["Mode=Dark, State=Idle"])
        // Dark×Clicked and Light×Idle and Light×Clicked would be missing if axes inferred only from present;
        // axes only contain seen values, so missingCombinations is empty unless options come from definitions.
        XCTAssertEqual(sparse.axes["Mode"], ["Dark"])
    }

    func testTypeIdentifier() {
        XCTAssertEqual(SwiftUIGenerator.typeIdentifier("Toggles / Switches"), "TogglesSwitches")
        XCTAssertEqual(SwiftUIGenerator.typeIdentifier("2D"), "_2D")
        XCTAssertEqual(SwiftUIGenerator.num(0.02), "0.02")
        XCTAssertEqual(SwiftUIGenerator.num(54), "54")
    }
}
