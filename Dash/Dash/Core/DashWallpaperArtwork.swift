//
//  DashWallpaperArtwork.swift
//  Dash
//
//  Renders one `DashWallpaper`'s actual artwork — a supplied local image if
//  present, else the built-in procedural field, else a flat fallback. No shell
//  chrome, no legibility overlays: just "what does this wallpaper look like".
//
//  Extracted from `Shell/DashShellBackground.swift` (M8.3) so it can be shared
//  by two very different consumers without either importing the other:
//    • `Shell/DashShellBackground.swift` composites this with the shell's own
//      dark-corner / bottom legibility gradients for the live background.
//    • The self-contained Settings feature's Wallpaper picker
//      (`Features/Settings/SettingsWallpaperView.swift`) uses this bare, as a
//      small preview swatch, with no shell-specific overlay — a feature may
//      never import `Shell/`, so the one rendering system both need lives here
//      in `Core/`, next to the `DashWallpaper` model itself (M8.3 §5/§10: reuse
//      the existing wallpaper type, never build a second rendering system).
//

import SwiftUI

/// The resolved artwork for one `DashWallpaper` — nothing else layered on top.
struct DashWallpaperArtwork: View {

    let wallpaper: DashWallpaper

    var body: some View {
        if let fileURL = wallpaper.customFileURL, let image = Self.image(contentsOf: fileURL) {
            // A custom (user-imported) wallpaper — a file in the app's own
            // sandbox, not a bundle asset.
            image
                .resizable()
                .scaledToFill()
        } else if let name = wallpaper.assetName, let image = DashLocalAssets.image(named: name) {
            image
                .resizable()
                .scaledToFill()
        } else if wallpaper.hasProceduralFallback {
            ProceduralField()
        } else {
            // No asset, no procedural fallback declared — a neutral dark
            // ground rather than `DashTheme`'s `Color.dashBackground` (a
            // feature may not import `Shell/`, and this view lives in `Core/`
            // precisely so a feature can render it).
            Color(white: 0.05)
        }
    }

    private static func image(contentsOf url: URL) -> Image? {
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: uiImage)
    }
}

/// The committed default field — warm burgundy / crimson / ember cooling to a
/// deep indigo-black toward the lower-left. Large smooth shapes, no decorative
/// noise; enough dark area for translucent panels to stay legible.
struct ProceduralField: View {

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.55], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
                ],
                colors: [
                    c(0.26, 0.08, 0.10), c(0.40, 0.13, 0.09), c(0.49, 0.19, 0.11),
                    c(0.22, 0.07, 0.16), c(0.19, 0.06, 0.10), c(0.33, 0.10, 0.12),
                    c(0.08, 0.06, 0.15), c(0.05, 0.05, 0.09), c(0.05, 0.05, 0.08),
                ]
            )

            // Ember bloom, high and to the right.
            RadialGradient(
                colors: [c(0.58, 0.22, 0.12).opacity(0.42), .clear],
                center: UnitPoint(x: 0.86, y: 0.06),
                startRadius: 0, endRadius: 900
            )
            // Magenta bloom, mid-left.
            RadialGradient(
                colors: [c(0.34, 0.09, 0.28).opacity(0.34), .clear],
                center: UnitPoint(x: 0.10, y: 0.42),
                startRadius: 0, endRadius: 820
            )
        }
    }

    private func c(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }
}

#if DEBUG
#Preview {
    DashWallpaperArtwork(wallpaper: WallpaperCatalog.default)
        .ignoresSafeArea()
}
#endif
