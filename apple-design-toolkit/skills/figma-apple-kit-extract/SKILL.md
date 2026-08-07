---
name: figma-apple-kit-extract
description: Extract exact design specs (fills, radii, metrics, effects) from Apple's official UI kits in Figma libraries and map them to native SwiftUI — search, import, read resolved geometry programmatically. Also covers building parametric app-icon marks in Figma and exporting them to a correct .icns. Use when matching an app's look to Apple's macOS/iOS UI kits from Figma.
---

# Figma Apple-Kit Extraction Pipeline

Turn Apple's official Figma UI kits (macOS 27, iOS 27, watchOS, visionOS) into exact native-code values. Never eyeball a control again — read the component's real anatomy.

## Prerequisites

- Figma MCP server authenticated (`whoami` returns the user's plan).
- The Apple kit attached **as a library** to some file the user owns.

**Cover-only trap:** a community "duplicate" of a kit frequently contains ONLY the Cover page — 1 frame, no components. Verify with `get_metadata` (no `nodeId` → returns the page list). If the only page is `Cover`, stop: ask the user to add the kit through **Assets → Add more libraries** in any file, then work from that file's key. Do not try to reconstruct components from the cover art.

## Pipeline

1. **`get_libraries(fileKey)`** on a file with the kits attached → each library's `libraryKey`. Users often have many (macOS 26/27, iOS 26/27, watchOS, visionOS, Material 3…), so always scope the next step.

2. **`search_design_system(query, fileKey, includeLibraryKeys=[kitKey])`** — the matcher is **single-term**. `"button"` works; `"window panel material glass button"` returns an empty set. Query one concept at a time: button, switch, window, toolbar, slider, menu, sidebar. Results carry `assetType` (`component_set` vs `component`) and `componentKey`.

3. **Import + read anatomy in ONE `use_figma` call** — cheaper and more precise than `get_design_context` when you want *values* rather than layout code:

```js
// match the importer to assetType from the search result
const set  = await figma.importComponentSetByKeyAsync(COMPONENT_KEY); // component_set
// const c = await figma.importComponentByKeyAsync(COMPONENT_KEY);    // component
const inst = set.defaultVariant.createInstance();
figma.currentPage.appendChild(inst);

const compact = (n, d) => {
  const o = { name: n.name, type: n.type, w: n.width, h: n.height };
  if ("cornerRadius" in n && typeof n.cornerRadius === "number") o.r = n.cornerRadius;
  if ("fills" in n && Array.isArray(n.fills)) o.fills = n.fills.map(f =>
    f.type === "SOLID"
      ? { s: [f.color.r*255|0, f.color.g*255|0, f.color.b*255|0], o: f.opacity ?? 1 }
      : { t: f.type });
  if ("effects" in n && n.effects.length) o.fx = n.effects.map(e => ({ t: e.type, r: e.radius, y: e.offset?.y, a: e.color?.a }));
  if (d > 0 && "children" in n) o.ch = n.children.slice(0, 6).map(c => compact(c, d - 1));
  return o;
};
return { anatomy: compact(inst, 3), variants: set.children.map(c => c.name) };
```

4. **Kit variables**: `figma.variables.importVariableByKeyAsync(key)` → `Object.values(v.valuesByMode)[0]`. Values are often a `VARIABLE_ALIAS` — resolve by importing the alias id, or just use the instantiated component's measured geometry, which is ground truth anyway.

**`get_design_context` gotcha:** it errors with *"You currently have nothing selected"* when the file has no active selection in the desktop app. For kit reads, prefer the import-and-measure path above; it needs no selection.

## Reading the anatomy (macOS 27 Liquid Glass)

- Buttons are true capsules (`cornerRadius: 1000`). The glass plate is **stacked translucent fills** (e.g. black 25% + white 25% + `#444` 60% + `#F8F8F8` 20%) — replicate as layered `Capsule().fill()` overlays, never one averaged colour.
- A `GLASS` effect plus `INNER_SHADOW` pairs at ±40 y-offset encodes the **specular top and bottom edges**. The bottom counter-light is the most-forgotten cue; without it a panel reads as paper.
- Shadows in the kit are whisper-soft (radius 15, y 8, alpha **0.02**). Resist darkening them. For a floating panel, layer a tight contact shadow (r≈3, y1) with a wide faint ambient one (r≈14, y8) and scale both down in light mode — one heavy blur reads as a grey smudge.
- Switch: 54 × 24 capsule track (black 85% off), knob is a **wide pill 32 × 20** white with a y3 shadow. SwiftUI's stock `Toggle` is the older geometry — build a custom view.
- **Variant selection matters for renders:** kit components ship `Mode=Dark` / `Mode=Light` variants. A dark variant placed on a dark backdrop is invisible. Filter `set.children` by name for the mode and state you need (`"Mode=Dark"`, `"State=Idle"`) rather than taking `defaultVariant`.

## Mapping to SwiftUI

- Extracted 0-255 colours → `Color(red: x/255, green: …, blue: …)`.
- Layered fills → stacked `.overlay(Capsule().fill(...))`.
- **Adaptive appearance for free:** use semantic `Color.primary.opacity(x)` for control fills, text and symbols (white in dark, black in light) instead of hardcoded `.white`. Do NOT force `.environment(\.colorScheme, .dark)` — it defeats the kit's own light/dark system. Keep *specular* whites literally white; they are physical highlights, not semantic colours.
- Real glass requires `NSVisualEffectView` with `blendingMode = .behindWindow` — see the `macos-app-no-xcode` skill; `.ultraThinMaterial` in a borderless panel silently renders flat.

## Building a parametric icon mark

For faceted / folded-paper marks, compute the geometry in JS inside `use_figma` rather than hand-writing polygon points:

1. Define the mark as a **polyline** of ~6-9 vertices.
2. Offset each vertex by a **miter normal**: `m = normalize(n₁+n₂)`, `s = h / dot(m, n₁)`, clamped to ~2.5h so sharp reversals don't spike. Each segment becomes a quad `[topᵢ, topᵢ₊₁, botᵢ₊₁, botᵢ]`.
3. **Shade each facet by its own normal** against one light `L`: `t = (dot(n, L)+1)/2`, mapped through a colour ramp. This is what makes folds read as physical rather than decorative.
   - Watch the normal's sign: `perp(d) = (-dy, dx)` points **down** in SVG's y-down space. For a top-left light, shade with `(dy, -dx)` so flat horizontals come out bright.
4. Add paper thickness by drawing the full ribbon outline once, offset ~10px down-right in a darker colour, *behind* the facets; add 2px crease lines at fold vertices.
5. Big Sur grid: artwork inside an 824×824 squircle at (100,100) r185 on a 1024 canvas; mark ~62% of width.

Design note: pick a mark that means something specific to the app. Generic energy/power glyphs (lightning bolts especially) are the most crowded space in icon design — a mark derived from the product's actual name or function reads as considered.

## Icon export → .icns (with the transparency trap)

**`frame.fills = []` in Figma is NOT sufficient.** The exported PNG can still come back with opaque corner pixels (alpha channel present, corners white), which shows as a white card behind your icon in Finder and the Dock. Always re-clip locally:

```swift
// clip 1024 artwork to the macOS squircle on a transparent canvas
NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
             xRadius: 185, yRadius: 185).addClip()
img.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
```

`sips -g hasAlpha` reports *yes* even when corners are opaque — it is not a sufficient check. Verify visually against other Dock icons.

Full chain: `download_assets` (png @1024) → local squircle clip → `sips -z` for 16/32/128/256/512 + @2x into `AppIcon.iconset/` → `iconutil -c icns` → copy into `Contents/Resources/` + `CFBundleIconFile` → `touch app`, `lsregister -f app`, `killall Finder Dock` to bust icon caches.
