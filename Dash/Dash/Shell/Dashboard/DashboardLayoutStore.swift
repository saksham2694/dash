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
    /// `.v2` — the M5.5.2a two-column grid; `.v1` layouts (6 × 4) are abandoned.
    static let storageKey = "shell.dashboardLayout.v2"

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

    /// Move the placement with `id` to a new grid `origin`. Committed once, when
    /// a drag interaction ends (M5.4.3); `canMovePlacement` drives the live
    /// feedback in between without persisting.
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

    /// Outcome of `addWidget` — distinguishes "no room" (a normal, user-facing
    /// state the editor should explain) from a structural rejection.
    enum WidgetAddOutcome: Equatable, Sendable {
        case added(UUID)
        case noSpace
        case rejected
    }

    /// Add a widget for `featureID` at `size`, auto-placing it in the first free
    /// grid slot (top-left, row by row — see `DashboardLayoutEditor.firstFreeOrigin`).
    /// The caller never chooses coordinates. Feature-agnostic: `featureID` is
    /// opaque and the picker is responsible for only offering sizes the feature
    /// supports.
    @discardableResult
    func addWidget(
        featureID: FeatureID,
        size: ComponentSize,
        toPageAt pageIndex: Int = 0
    ) -> WidgetAddOutcome {
        guard size.isWidget, layout.pages.indices.contains(pageIndex) else { return .rejected }
        guard let origin = DashboardLayoutEditor.firstFreeOrigin(
            for: size, onPageAt: pageIndex, in: layout, grid: grid
        ) else {
            return .noSpace
        }
        let placement = WidgetPlacement(featureID: featureID, size: size, origin: origin)
        return addPlacement(placement, toPageAt: pageIndex) ? .added(placement.id) : .rejected
    }

    // MARK: - Interaction queries (M5.4.3)
    //
    //  Non-mutating, non-persisting "would this be valid?" checks. They let a
    //  drag / resize gesture show live feedback and remember the last valid
    //  position; the actual commit still goes through `movePlacement` /
    //  `updatePlacementSize` when the interaction ends.

    /// Whether moving the placement with `id` to `origin` would keep the layout
    /// structurally valid (in bounds, no overlap). `false` for an unknown id.
    func canMovePlacement(id: UUID, to origin: GridPoint) -> Bool {
        guard placementExists(id) else { return false }
        return isStructurallyValid(DashboardLayoutEditor.moving(placementID: id, to: origin, in: layout))
    }

    /// Whether resizing the placement with `id` to `size` (origin unchanged)
    /// would keep the layout structurally valid. `false` for an unknown id.
    func canResizePlacement(id: UUID, to size: ComponentSize) -> Bool {
        guard placementExists(id) else { return false }
        return isStructurallyValid(DashboardLayoutEditor.settingSize(of: id, to: size, in: layout))
    }

    private func placementExists(_ id: UUID) -> Bool {
        layout.allPlacements.contains { $0.id == id }
    }

    private func isStructurallyValid(_ candidate: DashboardLayout) -> Bool {
        DashboardLayoutValidator.isStructurallyValid(candidate, grid: grid)
    }

    /// Persist `candidate` iff it is structurally valid against the grid.
    private func applyIfValid(_ candidate: DashboardLayout) -> Bool {
        guard isStructurallyValid(candidate) else { return false }
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
