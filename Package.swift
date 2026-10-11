// swift-tools-version:5.9
//
// Executable code for the four skills in apple-design-toolkit.
// Pure logic builds and tests on Linux; macOS-only steps (codesign, sips,
// iconutil, launchctl, CoreGraphics paths) sit behind #if canImport/#if os.
import PackageDescription

let package = Package(
    name: "AppleDesignToolkit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KitGeometry", targets: ["KitGeometry"]),
        .library(name: "FigmaKitExtract", targets: ["FigmaKitExtract"]),
        .library(name: "RootAgent", targets: ["RootAgent"]),
        .library(name: "NoXcodeBuild", targets: ["NoXcodeBuild"]),
        .library(name: "GatedToolPreflight", targets: ["GatedToolPreflight"]),
        .executable(name: "adt-figma", targets: ["adt-figma"]),
        .executable(name: "adt-build", targets: ["adt-build"]),
        .executable(name: "adt-rootagent", targets: ["adt-rootagent"]),
    ],
    targets: [
        .target(name: "ToolkitCore"),
        .target(name: "KitGeometry"),
        .target(name: "FigmaKitExtract", dependencies: ["ToolkitCore"]),
        .target(name: "RootAgent", dependencies: ["ToolkitCore"]),
        .target(name: "NoXcodeBuild", dependencies: ["ToolkitCore"]),
        .target(name: "GatedToolPreflight"),
        .executableTarget(name: "adt-figma", dependencies: ["FigmaKitExtract"]),
        .executableTarget(name: "adt-build", dependencies: ["NoXcodeBuild"]),
        .executableTarget(name: "adt-rootagent", dependencies: ["RootAgent"]),
        .testTarget(name: "ToolkitCoreTests", dependencies: ["ToolkitCore"]),
        .testTarget(name: "KitGeometryTests", dependencies: ["KitGeometry"]),
        .testTarget(name: "FigmaKitExtractTests", dependencies: ["FigmaKitExtract"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "RootAgentTests", dependencies: ["RootAgent"]),
        .testTarget(name: "NoXcodeBuildTests", dependencies: ["NoXcodeBuild"]),
        .testTarget(name: "GatedToolPreflightTests", dependencies: ["GatedToolPreflight"]),
    ]
)
