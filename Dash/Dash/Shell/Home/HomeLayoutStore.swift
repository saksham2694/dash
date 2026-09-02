//
//  HomeLayoutStore.swift
//  Dash
//
//  App-scoped owner of the *persisted* Home launcher arrangement. Loads on init,
//  exposes the current `HomeLayout` as observable state, and writes back through
//  `UserDefaults` when it is replaced.
//
//  Mirrors `DashboardLayoutStore` (and the project's other small stores): storage
//  only, no networking, no feature knowledge, no runtime feature state.
//
//  Persistence is a `Codable` JSON envelope carrying a schema `version` under a
//  namespaced key. Anything that can't be decoded, carries an unrecognised
//  version, or has duplicate placement ids falls back to the seed.
//

import Combine
import Foundation

@MainActor
final class HomeLayoutStore: ObservableObject {

    /// Namespaced key. A breaking schema change bumps the `.vN` suffix; the
    /// envelope `version` guards the current line.
    static let storageKey = "shell.homeLayout.v1"

    /// Current envelope schema version.
    static let schemaVersion = 1

    /// The live layout. Read by `HomeSpaceView`.
    @Published private(set) var layout: HomeLayout

    private let defaults: UserDefaults

    /// The layout used when nothing valid is persisted. Also what
    /// `resetToDefault()` restores.
    let seed: HomeLayout

    init(seed: HomeLayout, defaults: UserDefaults = .standard) {
        self.seed = seed
        self.defaults = defaults
        self.layout = Self.loadValid(from: defaults) ?? seed
    }

    // MARK: - Mutation

    /// Swap in a new layout and persist it. (No editing UI calls this yet in
    /// M5.3.0 — this is the save path the foundation provides.)
    func replace(with newLayout: HomeLayout) {
        layout = newLayout
        persist(newLayout)
    }

    /// Restore and persist the seed layout.
    func resetToDefault() {
        replace(with: seed)
    }

    // MARK: - Persistence

    private func persist(_ layout: HomeLayout) {
        let envelope = StoredLayout(version: Self.schemaVersion, layout: layout)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Decode the persisted layout, returning `nil` (→ caller uses the seed) if
    /// it is missing, undecodable, a wrong schema version, or has duplicate
    /// placement ids (which would break SwiftUI identity). Unknown `featureID`s
    /// are *not* rejected here — the store has no registry; the shell handles
    /// unresolved tiles at render time.
    private static func loadValid(from defaults: UserDefaults) -> HomeLayout? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        guard
            let envelope = try? JSONDecoder().decode(StoredLayout.self, from: data),
            envelope.version == schemaVersion
        else {
            return nil
        }
        let ids = envelope.layout.allApps.map(\.id)
        guard Set(ids).count == ids.count else { return nil }
        return envelope.layout
    }

    /// The on-disk shape. Kept private so the schema version never leaks into
    /// the domain model.
    private struct StoredLayout: Codable {
        var version: Int
        var layout: HomeLayout
    }
}
