//
//  DashboardCollectionStore.swift
//  Dash
//
//  App-scoped owner of the *persisted* dashboard collection (M5.6). It is the one
//  place responsible for:
//    • the dashboard records + which one is active,
//    • add / remove / select / rename,
//    • the validated widget-mutation vocabulary — applied to the ACTIVE dashboard,
//    • persistence,
//    • migration from the single-dashboard format (`shell.dashboardLayout.v2`).
//
//  Replaces `DashboardLayoutStore`: same validated-mutation surface (`addWidget`,
//  `removePlacement`, `updatePlacementSize`, `movePlacement`, `canMovePlacement`,
//  `canResizePlacement`, `replace(with:)`, `resetToDefault`), now scoped to the
//  active dashboard. The pure work still goes through `DashboardLayoutEditor` and
//  `DashboardLayoutValidator` — nothing is reimplemented.
//
//  Mirrors the project's other small stores: storage only, no networking, no
//  feature knowledge, no runtime feature state. Features remain unaware that a
//  dashboard collection exists — they only ever see `WidgetPlacement` /
//  `DashFeature`.
//
//  Persistence is a `Codable` JSON envelope carrying a schema `version` under a
//  namespaced key. Anything that can't be decoded — wrong version, or a
//  structurally invalid collection — falls back to a fresh single dashboard.
//

import Combine
import Foundation

@MainActor
final class DashboardCollectionStore: ObservableObject {

    /// Namespaced key for the collection format.
    static let storageKey = "shell.dashboards.v1"

    /// The single-dashboard key this migrates from (written by the retired
    /// `DashboardLayoutStore`).
    static let legacyStorageKey = "shell.dashboardLayout.v2"

    /// Current envelope schema version.
    static let schemaVersion = 1

    /// The live collection. Read by `DashboardSpaceView` / `DashboardManagerView`.
    @Published private(set) var collection: DashboardCollection

    private let defaults: UserDefaults
    private let grid: DashboardGrid

    /// The layout a freshly-seeded first dashboard gets. Also what
    /// `resetToDefault()` restores the active dashboard to.
    let seed: DashboardLayout

    /// The default name for the first dashboard on a fresh install / migration.
    static let firstDashboardName = "Dashboard"

    init(
        seed: DashboardLayout,
        defaults: UserDefaults = .standard,
        grid: DashboardGrid = .standard
    ) {
        self.seed = seed
        self.defaults = defaults
        self.grid = grid

        if let loaded = Self.loadCollection(from: defaults, grid: grid) {
            self.collection = loaded
        } else if let migrated = Self.migrateLegacy(from: defaults, grid: grid) {
            self.collection = migrated
            Self.persist(migrated, to: defaults)
            // Remove the old key so a later launch never migrates again (→ no
            // duplicate dashboard).
            defaults.removeObject(forKey: Self.legacyStorageKey)
        } else {
            self.collection = DashboardCollection(
                single: DashboardRecord(name: Self.firstDashboardName, layout: seed)
            )
            // Nothing persisted yet — matches the retired store's behaviour of
            // not writing the seed until a real change.
        }
    }

    // MARK: - Active dashboard (drop-in surface for the dashboard editor)

    /// The active dashboard's layout. Read by `DashboardSpaceView`.
    var layout: DashboardLayout { collection.activeLayout }

    /// The active dashboard's display name.
    var activeName: String { collection.active.name }

    /// The active dashboard's id.
    var activeID: UUID { collection.activeID }

    /// Number of dashboards.
    var dashboardCount: Int { collection.count }

    /// Replace the active dashboard's layout and persist. Unconditional — the
    /// validated methods below check first.
    func replace(with newLayout: DashboardLayout) {
        collection.setActiveLayout(newLayout)
        persist()
    }

    /// Restore + persist the seed layout for the active dashboard.
    func resetToDefault() {
        replace(with: seed)
    }

    // MARK: - Collection management

    /// Switch the active dashboard. No-op for an unknown id.
    func select(id: UUID) {
        guard id != collection.activeID, collection.contains(id) else { return }
        collection.select(id)
        persist()
    }

    /// Add a new, empty dashboard and make it active. Returns its id.
    @discardableResult
    func addDashboard(name: String? = nil) -> UUID {
        let resolved = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (resolved?.isEmpty == false ? resolved! : defaultName(for: collection.count + 1))
        let id = collection.addDashboard(name: finalName, layout: Self.emptyLayout)
        persist()
        return id
    }

    /// Remove a dashboard. Refused (`false`) when it is the last one. If it was
    /// active, another dashboard is selected deterministically.
    @discardableResult
    func removeDashboard(id: UUID) -> Bool {
        let removed = collection.removeDashboard(id)
        if removed { persist() }
        return removed
    }

    /// Rename a dashboard. Empty / whitespace-only names are ignored.
    func renameDashboard(id: UUID, to name: String) {
        collection.rename(id, to: name)
        persist()
    }

    // MARK: - Validated widget mutations (active dashboard only)

    typealias WidgetAddOutcome = DashboardWidgetAddOutcome

    @discardableResult
    func removePlacement(id: UUID) -> Bool {
        guard placementExists(id) else { return false }
        return applyIfValid(DashboardLayoutEditor.removing(placementID: id, from: layout))
    }

    @discardableResult
    func updatePlacementSize(id: UUID, to size: ComponentSize) -> Bool {
        guard placementExists(id) else { return false }
        return applyIfValid(DashboardLayoutEditor.settingSize(of: id, to: size, in: layout))
    }

    @discardableResult
    func movePlacement(id: UUID, to origin: GridPoint) -> Bool {
        guard placementExists(id) else { return false }
        return applyIfValid(DashboardLayoutEditor.moving(placementID: id, to: origin, in: layout))
    }

    @discardableResult
    func addPlacement(_ placement: WidgetPlacement, toPageAt pageIndex: Int = 0) -> Bool {
        guard layout.pages.indices.contains(pageIndex) else { return false }
        return applyIfValid(DashboardLayoutEditor.adding(placement, toPageAt: pageIndex, in: layout))
    }

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

    // MARK: - Interaction queries (non-mutating, non-persisting)

    func canMovePlacement(id: UUID, to origin: GridPoint) -> Bool {
        guard placementExists(id) else { return false }
        return isStructurallyValid(DashboardLayoutEditor.moving(placementID: id, to: origin, in: layout))
    }

    func canResizePlacement(id: UUID, to size: ComponentSize) -> Bool {
        guard placementExists(id) else { return false }
        return isStructurallyValid(DashboardLayoutEditor.settingSize(of: id, to: size, in: layout))
    }

    // MARK: - Private

    /// An added dashboard starts empty — one page, no widgets.
    private static let emptyLayout = DashboardLayout(pages: [DashboardPage()])

    private func defaultName(for ordinal: Int) -> String {
        ordinal <= 1 ? Self.firstDashboardName : "\(Self.firstDashboardName) \(ordinal)"
    }

    private func placementExists(_ id: UUID) -> Bool {
        layout.allPlacements.contains { $0.id == id }
    }

    private func isStructurallyValid(_ candidate: DashboardLayout) -> Bool {
        DashboardLayoutValidator.isStructurallyValid(candidate, grid: grid)
    }

    private func applyIfValid(_ candidate: DashboardLayout) -> Bool {
        guard isStructurallyValid(candidate) else { return false }
        replace(with: candidate)
        return true
    }

    // MARK: - Persistence

    private func persist() {
        Self.persist(collection, to: defaults)
    }

    private static func persist(_ collection: DashboardCollection, to defaults: UserDefaults) {
        let envelope = StoredCollection(version: schemaVersion, collection: collection)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// Decode the persisted collection, or `nil` (→ migrate / seed) when it is
    /// missing, undecodable, a wrong version, or structurally invalid.
    private static func loadCollection(from defaults: UserDefaults, grid: DashboardGrid) -> DashboardCollection? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        guard
            let envelope = try? JSONDecoder().decode(StoredCollection.self, from: data),
            envelope.version == schemaVersion,
            envelope.collection.isStructurallyValid(grid: grid)
        else {
            return nil
        }
        return envelope.collection
    }

    /// Build a one-dashboard collection from a valid single-dashboard layout
    /// persisted by the retired `DashboardLayoutStore`. `nil` when there is no
    /// legacy data or it is not valid on the current grid.
    private static func migrateLegacy(from defaults: UserDefaults, grid: DashboardGrid) -> DashboardCollection? {
        guard let data = defaults.data(forKey: legacyStorageKey) else { return nil }
        guard
            let envelope = try? JSONDecoder().decode(LegacyStoredLayout.self, from: data),
            envelope.version == 1,
            DashboardLayoutValidator.isStructurallyValid(envelope.layout, grid: grid)
        else {
            return nil
        }
        return DashboardCollection(
            single: DashboardRecord(name: firstDashboardName, layout: envelope.layout)
        )
    }

    /// The on-disk shape for the collection.
    private struct StoredCollection: Codable {
        var version: Int
        var collection: DashboardCollection
    }

    /// The retired `DashboardLayoutStore`'s on-disk shape — read once for migration.
    private struct LegacyStoredLayout: Codable {
        var version: Int
        var layout: DashboardLayout
    }
}

/// Outcome of `addWidget` — "no room" (a normal, user-facing state) vs a
/// structural rejection. Free function-style enum so it reads the same as the
/// retired store's nested `WidgetAddOutcome`.
nonisolated enum DashboardWidgetAddOutcome: Equatable, Sendable {
    case added(UUID)
    case noSpace
    case rejected
}
