//
//  DashboardLayoutStore.swift
//  Dash
//
//  App-scoped owner of the *persisted* dashboard layout. Loads on init, exposes
//  the current `DashboardLayout` as observable state, and writes back through
//  `UserDefaults` when the layout is replaced.
//
//  Mirrors the project's other small single-purpose stores (`LocationStore`,
//  `KnownDeviceStore`, `DestinationStore`): storage only, no networking, no
//  feature knowledge, no runtime feature state.
//
//  Persistence is a `Codable` JSON envelope carrying a schema `version` under a
//  namespaced key. Anything that can't be decoded — or decodes to a structurally
//  invalid layout, or carries an unrecognised version — falls back to the seed.
//

import Combine
import Foundation

@MainActor
final class DashboardLayoutStore: ObservableObject {

    /// Namespaced key. A breaking schema change bumps the `.vN` suffix (old data
    /// is then simply ignored); the envelope `version` guards the current line.
    static let storageKey = "shell.dashboardLayout.v1"

    /// Current envelope schema version.
    static let schemaVersion = 1

    /// The live layout. Read by `DashboardSpaceView`.
    @Published private(set) var layout: DashboardLayout

    private let defaults: UserDefaults
    private let grid: DashboardGrid

    /// The layout used when nothing valid is persisted. Also what
    /// `resetToDefault()` restores.
    let seed: DashboardLayout

    init(
        seed: DashboardLayout,
        defaults: UserDefaults = .standard,
        grid: DashboardGrid = .standard
    ) {
        self.seed = seed
        self.defaults = defaults
        self.grid = grid
        self.layout = Self.loadValid(from: defaults, grid: grid) ?? seed
    }

    // MARK: - Mutation

    /// Swap in a new layout and persist it. (No editing UI calls this yet in
    /// M5.2.0 — this is the save path the foundation provides.)
    func replace(with newLayout: DashboardLayout) {
        layout = newLayout
        persist(newLayout)
    }

    /// Restore and persist the seed layout.
    func resetToDefault() {
        replace(with: seed)
    }

    // MARK: - Persistence

    private func persist(_ layout: DashboardLayout) {
        let envelope = StoredLayout(version: Self.schemaVersion, layout: layout)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Decode the persisted layout, returning `nil` (→ caller uses the seed) if
    /// it is missing, undecodable, a wrong schema version, or structurally
    /// invalid against `grid`. Feature-id / supported-size checks are *not* done
    /// here — the store has no registry; the shell handles unresolved widgets at
    /// render time.
    private static func loadValid(from defaults: UserDefaults, grid: DashboardGrid) -> DashboardLayout? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        guard
            let envelope = try? JSONDecoder().decode(StoredLayout.self, from: data),
            envelope.version == schemaVersion,
            DashboardLayoutValidator.isStructurallyValid(envelope.layout, grid: grid)
        else {
            return nil
        }
        return envelope.layout
    }

    /// The on-disk shape. Kept private so the schema version never leaks into
    /// the domain model.
    private struct StoredLayout: Codable {
        var version: Int
        var layout: DashboardLayout
    }
}
