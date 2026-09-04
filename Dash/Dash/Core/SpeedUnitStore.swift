//
//  SpeedUnitStore.swift
//  Dash
//
//  App-scoped owner of the *persisted* Speedometer display-unit preference
//  (M8.3). Mirrors `WallpaperStore` exactly: storage only, no networking, no
//  feature knowledge, no UI.
//
//  Lives in `Core/`, not inside `Features/Speedometer/` or `Features/Settings/`,
//  because BOTH features need it and a feature never references another
//  feature (CLAUDE.md) — this is the shared seam the M8.3 spec calls for:
//
//      Settings → shared/app-level speed-unit preference → SpeedometerFeature
//
//  The Settings ▸ Speedometer screen calls `select(_:)`; the Speedometer
//  feature's live views (`SpeedometerGaugeView` / `SpeedometerCompactView`)
//  read `unit` via `@EnvironmentObject` — the same pattern they already use
//  for `LocationStore` — and forward it into `SpeedometerViewModel.setUnit(_:)`
//  (the M8.0 hook built for exactly this). Settings never touches
//  `SpeedometerEngine` or `SpeedometerViewModel`; Speedometer never persists a
//  unit of its own — this store is the ONLY place the preference is written or
//  read from disk.
//
//  `SpeedometerUnit` itself lives at `Features/SpeedometerUnit.swift` (M8.3) —
//  promoted out of `Features/Speedometer/` to sit alongside `ComponentSize`,
//  for the same reason: more than one feature now needs the vocabulary.
//

import Combine
import Foundation

@MainActor
final class SpeedUnitStore: ObservableObject {

    /// Namespaced key. A breaking change to the unit model bumps the `.vN`
    /// suffix; old values are then simply ignored (→ default).
    static let storageKey = "speedometer.unit.v1"

    /// The selected display unit. Read + persisted; never invalid. Defaults to
    /// km/h (`SpeedometerUnit.default`) until a preference has been saved.
    @Published private(set) var unit: SpeedometerUnit

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.unit = Self.loadValid(from: defaults) ?? .default
    }

    // MARK: - Mutation

    /// Choose a display unit and persist it. Persisting is idempotent; the
    /// `@Published` selection only churns on an actual change.
    func select(_ unit: SpeedometerUnit) {
        if unit != self.unit { self.unit = unit }
        defaults.set(unit.rawValue, forKey: Self.storageKey)
    }

    /// Restore and persist the default unit (km/h).
    func resetToDefault() {
        select(.default)
    }

    // MARK: - Persistence

    /// The persisted selection, or `nil` (→ caller uses the default) if it is
    /// missing or not a `SpeedometerUnit` this build knows.
    private static func loadValid(from defaults: UserDefaults) -> SpeedometerUnit? {
        guard let raw = defaults.string(forKey: storageKey) else { return nil }
        return SpeedometerUnit(rawValue: raw)
    }
}
