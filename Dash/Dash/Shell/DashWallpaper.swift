//
//  DashWallpaper.swift
//  Dash
//
//  The shell wallpaper model + catalog. One selectable background image behind
//  the whole Dash shell (Dashboard AND Home). A future Settings ▸ Appearance ▸
//  Wallpaper screen will change the selection through `WallpaperStore`; nothing
//  else about the shell has to change.
//
//  SDK-neutral value types — no SwiftUI. `DashShellBackground` maps the selected
//  `DashWallpaper` to an actual rendering (a local image if the developer has
//  supplied one, otherwise the built-in procedural field).
//

import Foundation

/// Stable identifier for a shell wallpaper. **Persisted** (its `rawValue` is
/// written to `UserDefaults`), so a case is never renamed or renumbered — only
/// added or, at most, deprecated.
nonisolated enum WallpaperID: String, CaseIterable, Codable, Sendable, Equatable {

    /// The warm burgundy / crimson / ember field Dash ships with — the default.
    case ember
}

/// A selectable shell wallpaper: a stable id, a display name for a future
/// settings list, and how to source its artwork.
nonisolated struct DashWallpaper: Identifiable, Equatable, Sendable {

    let id: WallpaperID

    /// Shown in a future Settings wallpaper picker.
    let displayName: String

    /// The `LocalAssets/` (or bundle) image name to prefer for this wallpaper,
    /// if one is present on the device. `nil` → always procedural.
    let assetName: String?

    /// Whether `DashShellBackground` can draw this wallpaper procedurally when no
    /// local image is available (so the shipped build is never blank).
    let hasProceduralFallback: Bool
}

/// The wallpapers Dash knows about. The **only** place the set is declared — a
/// future wallpaper is one entry here plus (optionally) a procedural branch in
/// `DashShellBackground`.
nonisolated enum WallpaperCatalog {

    static let all: [DashWallpaper] = [
        DashWallpaper(
            id: .ember,
            displayName: "Ember",
            assetName: "shell-wallpaper",
            hasProceduralFallback: true
        ),
    ]

    /// The wallpaper used when nothing valid is selected. Must be in `all`.
    static let `default`: DashWallpaper = all[0]

    /// The catalogued wallpaper for `id`, or the default if `id` is unknown
    /// (e.g. a value persisted by a newer build, then rolled back).
    static func wallpaper(_ id: WallpaperID) -> DashWallpaper {
        all.first { $0.id == id } ?? `default`
    }
}
