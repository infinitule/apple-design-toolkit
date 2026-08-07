---
name: macos-app-no-xcode
description: Build, sign, and ship a native SwiftUI macOS app (menu-bar accessory, floating island/HUD panels, GUI admin prompts, custom icns) from a single Swift file with swiftc — no Xcode project. Use when creating or iterating native Mac apps outside Xcode.
---

# Native macOS App Without an Xcode Project

Ship a real .app from one Swift file. Compile seconds, not minutes; the whole app is reviewable in a single source.

## Build + bundle

```bash
swiftc -O main.swift -o MacPulse          # top-level code REQUIRES the file be named main.swift
APP="$HOME/Applications/MyApp.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp binary "$APP/Contents/MacOS/"; cp Info.plist "$APP/Contents/"
cp AppIcon.icns resources... "$APP/Contents/Resources/"
codesign --force --deep -s - "$APP"       # ad-hoc is fine for local; required on Apple Silicon
```

Info.plist essentials: `CFBundleExecutable`, `CFBundleIdentifier`, `CFBundlePackageType=APPL`, `LSUIElement=true` (no Dock icon — island/menu-bar apps), `CFBundleIconFile=AppIcon`, `NSAppleEventsUsageDescription` if any osascript touches System Events.

## Floating island / HUD panel pattern

- `NSPanel` with `[.borderless, .nonactivatingPanel]`, `level = .statusBar`, `isOpaque=false`, `backgroundColor=.clear`, `hasShadow=false` (draw shadow in SwiftUI), `isMovableByWindowBackground=true`, `collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary]`.
- Override `canBecomeKey=true` + `keyDown` keyCode 53 for Esc.
- Expansion: resize the WINDOW frame (anchor top-center: keep `midX`/`maxY`) in sync with a SwiftUI spring — set frame BEFORE expanding, AFTER (delayed ~0.42 s) when collapsing. A transparent oversized window blocks clicks underneath — size snugly.
- Entry point without @main: top-level `let app = NSApplication.shared; app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()`.

## Real glass (the #1 gotcha)

`.ultraThinMaterial` inside a borderless `NSPanel` blends **within-window** only — it renders as a flat dark card and no amount of extra gradients will fix it. You need behind-window vibrancy:

```swift
struct GlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow        // or .popover / .underWindowBackground
        v.blendingMode = .behindWindow // ← the fix
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
```
Clip with `.clipShape(RoundedRectangle(cornerRadius:, style: .continuous))`. Requires `panel.isOpaque = false` + `backgroundColor = .clear`. Apple's real `.glassEffect` API needs macOS 26+, so hand-build below that: specular band top, **counter-light band at the bottom edge** (most-forgotten cue), gradient rim bright→dim, cursor-tracking radial highlight via `.onContinuousHover` with `.plusLighter`, and layered ambient + contact shadows.

Adaptive light/dark for free: use semantic `Color.primary.opacity(x)` for control fills and text (white in dark, black in light) and drop any forced `.environment(\.colorScheme, .dark)`. Keep specular whites literally white — they're physical, not semantic.

**Verifying glass:** `screencapture -o -l<windowid>` captures the window in isolation, where vibrancy has nothing to sample and renders **grey** — that grey is proof it's working, not a bug. To show refraction, region-capture (`screencapture -R x,y,w,h`) so the desktop behind is included.

## Privileged actions with GUI prompt

`Process` → `/usr/bin/osascript -e 'do shell script "…" with administrator privileges'` — shows the native password sheet, runs as root, no sudo/TTY needed. Run on a background queue; returncode 1 = user canceled. Escape embedded quotes/backslashes.

## Icon + registration

icns from any 1024 PNG: `sips -z $s $s` into `AppIcon.iconset/icon_{s}x{s}[@2x].png` (16/32/128/256/512 + @2x) → `iconutil -c icns`. After changing icon or plist: `touch "$APP"` + `lsregister -f "$APP"` + `killall Finder; killall Dock` (both auto-relaunch) or the old icon sticks in caches. Freshly-registered apps may not appear in app catalogs (e.g. screenshot-permission lists) until lsregister runs.

## Iteration loop

pkill the exact binary path → cp new binary → codesign → open. Keep sources in a durable dir (not session tmp) + git; a `build.sh` makes the repo one-command reproducible.
