//
//  MapAppearanceStore.swift
//  Dash
//
//  App-scoped owner of the *persisted* map visual-appearance preference.
//  Mirrors `SpeedUnitStore` / `WallpaperStore` exactly: storage only, no
//  networking, no map/SDK knowledge, no UI.
//
//  Lives in `Core/`, not inside `Features/Map/` or `Features/Settings/`,
//  because BOTH features need it and a feature never references another
//  feature (CLAUDE.md):
//
//      Settings → shared/app-level map-appearance preference → GoogleMapProvider
//
//  The Settings ▸ Maps ▸ Map Appearance screen calls `select(_:)`; the Map
//  feature's live views (`DashMapView` / `MapDashboardMapView`) read
//  `appearance` via `@EnvironmentObject` — the same pattern `SpeedUnitStore`
//  already uses for the Speedometer — and forward it into
//  `MapViewModel.setAppearance(_:)`. Settings never touches `MapViewModel` or
//  `GoogleMapProvider` directly; the Map feature never persists an appearance
//  of its own — this store is the ONLY place the preference is written or read
//  from disk.
//
//  `MapAppearance` itself lives at `Features/MapAppearance.swift` — the same
//  split `SpeedometerUnit` / `SpeedUnitStore` uses.
//

import Combine
import Foundation

@MainActor
final class MapAppearanceStore: ObservableObject {

    /// Namespaced key. A breaking change to the appearance model bumps the
    /// `.vN` suffix; old values are then simply ignored (→ default).
    static let storageKey = "map.appearance.v1"

    /// The selected map appearance. Read + persisted; never invalid. Defaults
    /// to `.standard` until a preference has been saved.
    @Published private(set) var appearance: MapAppearance

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = Self.loadValid(from: defaults) ?? .default
    }

    // MARK: - Mutation

    /// Choose a map appearance and persist it. Persisting is idempotent; the
    /// `@Published` selection only churns on an actual change.
    func select(_ appearance: MapAppearance) {
        if appearance != self.appearance { self.appearance = appearance }
        defaults.set(appearance.rawValue, forKey: Self.storageKey)
    }

    /// Restore and persist the default appearance (Standard).
    func resetToDefault() {
        select(.default)
    }

    // MARK: - Persistence

    /// The persisted selection, or `nil` (→ caller uses the default) if it is
    /// missing or not a `MapAppearance` this build knows.
    private static func loadValid(from defaults: UserDefaults) -> MapAppearance? {
        guard let raw = defaults.string(forKey: storageKey) else { return nil }
        return MapAppearance(rawValue: raw)
    }
}
