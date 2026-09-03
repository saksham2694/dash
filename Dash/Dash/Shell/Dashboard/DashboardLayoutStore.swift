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

    /// Swap in a new layout and persist it, unconditionally. The validated
    /// customization methods below go through here after checking the candidate;
    /// callers that already hold a trusted layout (tests, `resetToDefault`) use
    /// it directly.
    func replace(with newLayout: DashboardLayout) {
        layout = newLayout
        persist(newLayout)
    }

    /// Restore and persist the seed layout.
    func resetToDefault() {
        replace(with: seed)
    }

    // MARK: - Customization (M5.4.1)

    //  The smallest validated mutation vocabulary a Dashboard editor needs. Each
    //  builds the candidate layout with a pure `DashboardLayoutEditor` transform,
    //  checks it with `DashboardLayoutValidator` (the same structural gate
    //  `loadValid` uses), and only then persists via `replace(with:)`.
    //
    //  Returns `true` when the change was applied + persisted; `false` — leaving
    //  the stored layout untouched — when the target doesn't exist or the result
    //  would be structurally invalid (overlap / out-of-bounds / duplicate id /
    //  non-widget size). Feature-aware checks (unknown feature / unsupported
    //  size) belong to the caller, which has the `FeatureRegistry`.

    /// Remove the placement with `id`. No-op (`false`) if no placement matches.
    @discardableResult
    func removePlacement(id: UUID) -> Bool {
        guard placementExists(id) else { return false }
        return applyIfValid(DashboardLayoutEditor.removing(placementID: id, from: layout))
    }

    /// Change the `size` of the placement with `id`.
    @discardableResult
    func updatePlacementSize(id: UUID, to size: ComponentSize) -> Bool {
        guard placementExists(id) else { return false }
        return applyIfValid(DashboardLayoutEditor.settingSize(of: id, to: size, in: layout))
    }

    /// Move the placement with `id` to a new grid `origin` (the clean
    /// representation of "move / reorder"; drag interaction is M5.4.2).
    @discardableResult
    func movePlacement(id: UUID, to origin: GridPoint) -> Bool {
        guard placementExists(id) else { return false }
        return applyIfValid(DashboardLayoutEditor.moving(placementID: id, to: origin, in: layout))
    }

    /// Add `placement` to the page at `pageIndex` (default: the single Dashboard
    /// page). `false` if the page is out of range or the result is invalid.
    @discardableResult
    func addPlacement(_ placement: WidgetPlacement, toPageAt pageIndex: Int = 0) -> Bool {
        guard layout.pages.indices.contains(pageIndex) else { return false }
        return applyIfValid(DashboardLayoutEditor.adding(placement, toPageAt: pageIndex, in: layout))
    }

    private func placementExists(_ id: UUID) -> Bool {
        layout.allPlacements.contains { $0.id == id }
    }

    /// Persist `candidate` iff it is structurally valid against the grid.
    private func applyIfValid(_ candidate: DashboardLayout) -> Bool {
        guard DashboardLayoutValidator.isStructurallyValid(candidate, grid: grid) else { return false }
        replace(with: candidate)
        return true
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
