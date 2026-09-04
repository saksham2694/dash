//
//  DashShellBackground.swift
//  Dash
//
//  The shell's atmospheric background — one original, Dash-owned automotive
//  environment shared by the Dashboard and the Home launcher.
//
//  It resolves the *currently selected* wallpaper through `WallpaperStore` (a
//  future Settings ▸ Appearance ▸ Wallpaper screen changes the selection); it
//  does not hard-code one asset. For each wallpaper it prefers a local image the
//  developer has supplied in `LocalAssets/` (git-ignored — see `DashLocalAssets`)
//  and otherwise draws the built-in procedural field, so the shipped build is
//  never blank.
//
//  This view draws ONLY the wallpaper artwork + its legibility overlays. It does
//  not inset or round itself — the shell (`DashboardShell`) places it *inside*
//  the rounded, inset shell container so the wallpaper and the shell can never
//  drift apart (both derive from `DashMetrics.shell*`).
//

import SwiftUI

struct DashShellBackground: View {

    @EnvironmentObject private var wallpaperStore: WallpaperStore

    var body: some View {
        DashWallpaperView(wallpaper: wallpaperStore.selected)
    }
}

/// Renders one resolved `DashWallpaper`: a supplied local image if present, else
/// the procedural field, plus the dark-corner + bottom legibility gradients that
/// keep translucent panels and text readable whatever the artwork is.
struct DashWallpaperView: View {

    let wallpaper: DashWallpaper

    var body: some View {
        ZStack {
            artwork

            RadialGradient(
                colors: [.clear, Color.black.opacity(0.42)],
                center: .center, startRadius: 360, endRadius: 1240
            )
            LinearGradient(
                colors: [.clear, .clear, Color.black.opacity(0.28)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let name = wallpaper.assetName, let image = DashLocalAssets.image(named: name) {
            image
                .resizable()
                .scaledToFill()
        } else if wallpaper.hasProceduralFallback {
            ProceduralField()
        } else {
            Color.dashBackground
        }
    }
}

/// The committed default field — warm burgundy / crimson / ember cooling to a
/// deep indigo-black toward the lower-left. Large smooth shapes, no decorative
/// noise; enough dark area for translucent panels to stay legible.
private struct ProceduralField: View {

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

#Preview {
    DashWallpaperView(wallpaper: WallpaperCatalog.default)
        .ignoresSafeArea()
}
