//
//  DashWallpaper.swift
//  Dash
//
//  The shell wallpaper model + built-in catalog. One selectable background
//  image behind the whole Dash shell (Dashboard AND Home). The Settings ▸
//  Wallpaper screen (`Features/Settings/SettingsWallpaperView.swift`) changes
//  the selection through `WallpaperStore`; nothing else about the shell has
//  to change.
//
//  M8.5 splits wallpapers into two kinds, both rendered by the same
//  `DashWallpaperArtwork` and selected through the same `WallpaperStore`:
//    • BUILT-IN — bundled with the app, cannot be deleted, hand-declared in
//      `WallpaperCatalog.all` (no automatic folder scanning — deliberately
//      simple: adding one means a file in `Dash/Dash/BuiltInWallpapers/` PLUS
//      one entry here). The shipped default ("Ember") uses `assetName`,
//      resolved via `DashLocalAssets.image(named:)`; the rest point straight
//      at their bundled file (`fileURL(...)` below).
//    • CUSTOM — imported by the user from Photos (`WallpaperStore.addCustomWallpaper`),
//      copied into the app's own sandbox, and deletable. Like the non-default
//      built-ins, `customFileURL` points at a plain file rather than a bundle
//      asset name.
//
//  SDK-neutral value types — no SwiftUI. Lives in `Core/` (M8.3), not
//  `Shell/`, because it is genuinely shared: `Shell/DashShellBackground.swift`
//  renders it as the shell's background AND the self-contained Settings
//  feature renders it as a picker preview — a feature may not import `Shell/`,
//  so this model (and `WallpaperStore`, and the shared `DashWallpaperArtwork`
//  view) sit one layer down, the same way `LocationStore` does for GPS data.
//

import Foundation

/// Stable identifier for a wallpaper. **Persisted** (its `rawValue` is written
/// to `UserDefaults`), so a value is never reused for a different wallpaper.
/// A built-in's id is a fixed, hand-chosen string (`.ember`); a custom
/// (user-imported) wallpaper's id is a freshly generated UUID string,
/// assigned once at import — this is why `WallpaperID` is an open string
/// wrapper rather than a closed `enum` of cases: the set of ids is no longer
/// fixed at compile time once custom wallpapers exist.
nonisolated struct WallpaperID: RawRepresentable, Codable, Sendable, Equatable, Hashable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}

extension WallpaperID {
    /// The warm burgundy / crimson / ember field Dash ships with — the
    /// default built-in wallpaper.
    static let ember = WallpaperID(rawValue: "ember")
}

/// A selectable shell wallpaper: a stable id, a display name for the Settings
/// wallpaper list, and how to source its artwork — either a bundled asset
/// (built-in) or a copied file in the app's sandbox (custom).
nonisolated struct DashWallpaper: Identifiable, Equatable, Sendable {

    let id: WallpaperID

    /// Shown in the Settings wallpaper list.
    let displayName: String

    /// The `LocalAssets/` (or bundle) image name to prefer for the shipped
    /// default built-in wallpaper, if present on disk — resolved via
    /// `DashLocalAssets.image(named:)`. `nil` for anything sourced from a
    /// plain file (`customFileURL` instead): a discovered built-in or a
    /// custom wallpaper.
    let assetName: String?

    /// Whether `DashWallpaperArtwork` can draw this wallpaper procedurally
    /// when no asset image is available (so the shipped build is never
    /// blank). Only meaningful for the shipped default.
    let hasProceduralFallback: Bool

    /// Where this wallpaper's image FILE lives — a non-default built-in's
    /// bundled file (`Dash/Dash/BuiltInWallpapers/`) or a custom wallpaper's
    /// copied file in the app's sandbox. `nil` for the shipped default, which
    /// uses `assetName` instead.
    let customFileURL: URL?

    /// Whether the user can delete this wallpaper from Settings ▸ Wallpaper —
    /// true only for a custom (user-imported) wallpaper.
    let isDeletable: Bool

    /// The shipped default built-in wallpaper ("Ember") — bundled with the
    /// app, never deletable.
    init(id: WallpaperID, displayName: String, assetName: String?, hasProceduralFallback: Bool) {
        self.id = id
        self.displayName = displayName
        self.assetName = assetName
        self.hasProceduralFallback = hasProceduralFallback
        self.customFileURL = nil
        self.isDeletable = false
    }

    /// A non-default built-in wallpaper, hand-declared in
    /// `WallpaperCatalog.all` for a file in `Dash/Dash/BuiltInWallpapers/` —
    /// bundled with the app, never deletable, rendered as a plain file
    /// rather than a named asset.
    init(discoveredID id: WallpaperID, displayName: String, fileURL: URL) {
        self.id = id
        self.displayName = displayName
        self.assetName = nil
        self.hasProceduralFallback = false
        self.customFileURL = fileURL
        self.isDeletable = false
    }

    /// A custom wallpaper imported by the user — always deletable.
    init(customID id: WallpaperID, displayName: String, fileURL: URL) {
        self.id = id
        self.displayName = displayName
        self.assetName = nil
        self.hasProceduralFallback = false
        self.customFileURL = fileURL
        self.isDeletable = true
    }
}

/// The wallpapers Dash ships with, bundled in the app. The **only** place the
/// built-in set is declared — no automatic folder scanning: a new built-in is
/// its file dropped into `Dash/Dash/BuiltInWallpapers/` PLUS one entry added
/// here. Custom (user-imported) wallpapers are NOT part of this static
/// catalog — they live in `WallpaperStore.customWallpapers`, persisted
/// per-device.
nonisolated enum WallpaperCatalog {

    static let all: [DashWallpaper] = {
        let ember = DashWallpaper(
            id: .ember,
            displayName: "Ember",
            assetName: "shell-wallpaper",
            hasProceduralFallback: true
        )

        // Hand-declared, one per file actually present in
        // `Dash/Dash/BuiltInWallpapers/`. `compactMap` drops an entry
        // gracefully (rather than crashing) if a file is ever renamed/removed
        // without updating this list.
        let builtIns: [DashWallpaper?] = [
            builtInWallpaper(fileName: "Blue dark", extension: "jpeg", id: "blue-dark", displayName: "Blue Dark"),
            builtInWallpaper(fileName: "Blue light", extension: "jpeg", id: "blue-light", displayName: "Blue Light"),
            builtInWallpaper(fileName: "Red dark", extension: "jpeg", id: "red-dark", displayName: "Red Dark"),
        ]

        return [ember] + builtIns.compactMap { $0 }
    }()

    /// The wallpaper used when nothing valid is selected. Must be in `all`.
    static let `default`: DashWallpaper = all[0]

    /// The catalogued BUILT-IN wallpaper for `id`, or the default if `id`
    /// isn't a built-in (e.g. it names a custom wallpaper — callers that also
    /// need to resolve custom wallpapers should check
    /// `WallpaperStore.customWallpapers` first; `WallpaperStore.selected`
    /// does this).
    static func wallpaper(_ id: WallpaperID) -> DashWallpaper {
        all.first { $0.id == id } ?? `default`
    }

    /// Resolves one bundled file from `Dash/Dash/BuiltInWallpapers/` into a
    /// `DashWallpaper`. `nil` if the file isn't found in the built app bundle
    /// (so a typo here degrades to "wallpaper missing", never a crash).
    ///
    /// No `subdirectory:` argument: this project's file-system-synchronized
    /// group flattens loose resource files to the bundle root rather than
    /// preserving `BuiltInWallpapers/` as an actual subdirectory (confirmed
    /// by inspecting the built `.app` — `Blue dark.jpeg` etc. land right next
    /// to `Info.plist`), so the plain, no-subdirectory lookup is the one that
    /// actually finds them.
    private static func builtInWallpaper(fileName: String, extension ext: String, id: String, displayName: String) -> DashWallpaper? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: ext) else {
            return nil
        }
        return DashWallpaper(discoveredID: WallpaperID(rawValue: id), displayName: displayName, fileURL: url)
    }
}
