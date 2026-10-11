import Foundation
import ToolkitCore

/// Info.plist essentials from the macos-app-no-xcode skill.
public struct AppInfo: Equatable {
    public var name: String
    public var bundleID: String
    public var executable: String
    public var version: String
    public var build: String
    public var iconFile: String?
    /// Menu-bar / island apps: no Dock icon.
    public var lsUIElement: Bool
    public var appleEventsUsageDescription: String?
    public var minimumSystemVersion: String
    public var copyright: String?
    public var extra: [String: PlistValue]

    public init(name: String, bundleID: String, executable: String? = nil,
                version: String = "1.0.0", build: String = "1",
                iconFile: String? = "AppIcon", lsUIElement: Bool = true,
                appleEventsUsageDescription: String? = nil,
                minimumSystemVersion: String = "13.0",
                copyright: String? = nil,
                extra: [String: PlistValue] = [:]) {
        try! Identifier.validatePathComponent(name, field: "name")
        try! Identifier.validateReverseDNS(bundleID, field: "bundleID")
        let exe = executable ?? name
        try! Identifier.validatePathComponent(exe, field: "executable")
        self.name = name
        self.bundleID = bundleID
        self.executable = exe
        self.version = version
        self.build = build
        self.iconFile = iconFile
        self.lsUIElement = lsUIElement
        self.appleEventsUsageDescription = appleEventsUsageDescription
        self.minimumSystemVersion = minimumSystemVersion
        self.copyright = copyright
        self.extra = extra
    }

    public func plistValue() -> PlistValue {
        var d: [String: PlistValue] = [
            "CFBundleName": .string(name),
            "CFBundleDisplayName": .string(name),
            "CFBundleIdentifier": .string(bundleID),
            "CFBundleExecutable": .string(executable),
            "CFBundlePackageType": .string("APPL"),
            "CFBundleShortVersionString": .string(version),
            "CFBundleVersion": .string(build),
            "LSMinimumSystemVersion": .string(minimumSystemVersion),
            "LSUIElement": .bool(lsUIElement),
            "NSHighResolutionCapable": .bool(true),
        ]
        if let iconFile { d["CFBundleIconFile"] = .string(iconFile) }
        if let appleEventsUsageDescription {
            d["NSAppleEventsUsageDescription"] = .string(appleEventsUsageDescription)
        }
        if let copyright { d["NSHumanReadableCopyright"] = .string(copyright) }
        for (k, v) in extra { d[k] = v }
        return .dict(d)
    }

    public func xml() -> String { PlistWriter.xml(plistValue()) }
}
