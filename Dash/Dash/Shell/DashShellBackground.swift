//
//  DashShellBackground.swift
//  Dash
//
//  The shell's atmospheric background — one original, Dash-owned automotive
//  environment shared by the Dashboard and the Home launcher.
//
//  It resolves the *currently selected* wallpaper through `WallpaperStore`
//  (`Core/`, read by the Settings ▸ Wallpaper screen too — M8.3); it does not
//  hard-code one asset. The actual artwork (a local image if the developer has
//  supplied one in `LocalAssets/`, git-ignored — see `DashLocalAssets`, else
//  the built-in procedural field) is `Core/DashWallpaperArtwork`, shared with
//  the Settings feature's wallpaper preview; this view only adds the shell's
//  OWN legibility overlays on top, so the shipped build is never blank.
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

    private var artwork: some View {
        DashWallpaperArtwork(wallpaper: wallpaper)
    }
}

#Preview {
    DashWallpaperView(wallpaper: WallpaperCatalog.default)
        .ignoresSafeArea()
}
