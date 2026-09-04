//
//  WallpaperStore.swift
//  Dash
//
//  App-scoped owner of the *persisted* shell wallpaper selection. Loads on init,
//  exposes the current selection as observable state, and writes back through
//  `UserDefaults` when it changes.
//
//  Mirrors the project's other small single-purpose stores (`DashboardLayoutStore`,
//  `HomeLayoutStore`, `KnownDeviceStore`): storage only, no networking, no
//  feature knowledge, no UI. A future Settings ▸ Appearance ▸ Wallpaper feature
//  calls `select(_:)`; `DashShellBackground` reads `selected`.
//
//  Persistence is deliberately minimal — a single `WallpaperID.rawValue` string
//  under a namespaced, versioned key. A missing or unrecognised value falls back
//  to `WallpaperCatalog.default`.
//

import Combine
import Foundation

@MainActor
final class WallpaperStore: ObservableObject {

    /// Namespaced key. A breaking change to the wallpaper model bumps the `.vN`
    /// suffix; old values are then simply ignored (→ default).
    static let storageKey = "shell.wallpaper.v1"

    /// The selected wallpaper's id. Read + persisted; never invalid.
    @Published private(set) var selectedID: WallpaperID

    /// The resolved catalogue entry for the current selection.
    var selected: DashWallpaper { WallpaperCatalog.wallpaper(selectedID) }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedID = Self.loadValid(from: defaults) ?? WallpaperCatalog.default.id
    }

    // MARK: - Mutation

    /// Choose a wallpaper and persist it. Persisting is idempotent; the
    /// `@Published` selection only churns on an actual change.
    func select(_ id: WallpaperID) {
        if id != selectedID { selectedID = id }
        defaults.set(id.rawValue, forKey: Self.storageKey)
    }

    /// Restore and persist the default wallpaper.
    func resetToDefault() {
        select(WallpaperCatalog.default.id)
    }

    // MARK: - Persistence

    /// The persisted selection, or `nil` (→ caller uses the default) if it is
    /// missing or not a `WallpaperID` this build knows.
    private static func loadValid(from defaults: UserDefaults) -> WallpaperID? {
        guard let raw = defaults.string(forKey: storageKey) else { return nil }
        return WallpaperID(rawValue: raw)
    }
}
