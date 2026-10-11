import Foundation

/// Documented HUD / island panel recipe from the skill. This is reference
/// source a generator can emit; it is not executed on Linux.
public enum GlassPanelRecipe {
    /// The behind-window vibrancy fix. `.ultraThinMaterial` in a borderless
    /// NSPanel blends within-window only and renders as a flat dark card.
    public static let glassBackdrop = #"""
    import SwiftUI
    import AppKit

    struct GlassBackdrop: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let v = NSVisualEffectView()
            v.material = .hudWindow
            v.blendingMode = .behindWindow   // the entire fix
            v.state = .active
            return v
        }
        func updateNSView(_ v: NSVisualEffectView, context: Context) {}
    }
    """#

    public static let panelSetupNotes = """
    NSPanel with [.borderless, .nonactivatingPanel], level = .statusBar,
    isOpaque = false, backgroundColor = .clear, hasShadow = false (draw
    shadow in SwiftUI), isMovableByWindowBackground = true,
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary].
    Override canBecomeKey = true and keyDown keyCode 53 for Esc.
    Resize the WINDOW frame (anchor top-center: keep midX/maxY) in sync
    with a SwiftUI spring; set frame BEFORE expanding, AFTER (delayed
    ~0.42 s) when collapsing.
    """

    /// Hand-built glass cues below macOS 26 (where .glassEffect exists).
    public static let handBuiltGlassCues = [
        "specular band at the top edge",
        "counter-light band at the bottom edge (most-forgotten cue)",
        "gradient rim bright to dim",
        "cursor-tracking radial highlight via .onContinuousHover with .plusLighter",
        "layered ambient + contact shadows",
    ]
}
