import Foundation
import ToolkitCore

/// Pure description of a .app bundle layout. Creating directories and
/// copying files is the runner's job; this just decides the paths and the
/// Info.plist bytes so they can be unit-tested without touching a Mac.
public struct AppBundlePlan: Equatable {
    public var appName: String
    public var info: AppInfo
    public var resources: [String]          // filenames under Contents/Resources
    public var frameworks: [String]

    public init(info: AppInfo, resources: [String] = [], frameworks: [String] = []) {
        self.appName = info.name
        self.info = info
        self.resources = resources
        self.frameworks = frameworks
    }

    public var bundleName: String { appName + ".app" }
    public var contentsDir: String { "Contents" }
    public var macosDir: String { "Contents/MacOS" }
    public var resourcesDir: String { "Contents/Resources" }
    public var frameworksDir: String { "Contents/Frameworks" }
    public var executableRelPath: String { "Contents/MacOS/\(info.executable)" }
    public var infoPlistRelPath: String { "Contents/Info.plist" }

    /// Relative paths that must exist after assembly.
    public var requiredPaths: [String] {
        var p = [macosDir, resourcesDir, executableRelPath, infoPlistRelPath]
        if !frameworks.isEmpty { p.append(frameworksDir) }
        for r in resources { p.append("Contents/Resources/\(r)") }
        for f in frameworks { p.append("Contents/Frameworks/\(f)") }
        return p
    }

    public func absolute(_ root: String, _ rel: String) -> String {
        (root as NSString).appendingPathComponent(bundleName)
            .appending("/").appending(rel)
            .replacingOccurrences(of: "//", with: "/")
    }
}

/// Iconset layout and the `sips`/`iconutil` command plan from the skill.
public struct IconsetPlan: Equatable {
    public struct Entry: Equatable {
        public var filename: String
        public var pixels: Int
    }

    /// 16/32/128/256/512 + @2x (skill).
    public static let standard: [Entry] = [
        .init(filename: "icon_16x16.png", pixels: 16),
        .init(filename: "diana.k@example.org", pixels: 32),
        .init(filename: "icon_32x32.png", pixels: 32),
        .init(filename: "ivan.p@example.net", pixels: 64),
        .init(filename: "icon_128x128.png", pixels: 128),
        .init(filename: "wendy.h@example.net", pixels: 256),
        .init(filename: "icon_256x256.png", pixels: 256),
        .init(filename: "wendy.h@example.net", pixels: 512),
        .init(filename: "icon_512x512.png", pixels: 512),
        .init(filename: "walt.e@example.net", pixels: 1024),
    ]

    public var entries: [Entry]
    public init(entries: [Entry] = IconsetPlan.standard) { self.entries = entries }

    /// argv for each `sips -z` call. macOS-only at runtime.
    public func sipsCommands(sourcePNG: String, iconsetDir: String) -> [[String]] {
        entries.map { e in
            ["/usr/bin/sips", "-z", "\(e.pixels)", "\(e.pixels)", sourcePNG,
             "--out", (iconsetDir as NSString).appendingPathComponent(e.filename)]
        }
    }

    public func iconutilCommand(iconsetDir: String, outputICNS: String) -> [String] {
        ["/usr/bin/iconutil", "-c", "icns", iconsetDir, "-o", outputICNS]
    }
}
