//
//  DashboardCollection.swift
//  Dash
//
//  The persisted set of widget dashboards. A fresh install has exactly ONE
//  dashboard; the user can add / remove / rename more. Each dashboard owns an
//  independent `DashboardLayout` (widget selection, positions, sizes) — this type
//  only adds identity, a name, and an "active" pointer around the existing
//  `DashboardLayout` architecture; it does not reimplement it.
//
//  SDK-neutral and SwiftUI-free — plain `Codable` value types. The persistence
//  envelope, schema version and migration live in `DashboardCollectionStore`.
//
//  Invariants (upheld by `DashboardCollectionStore` on load and by every mutator
//  here): `dashboards` is non-empty and `activeID` names one of them.
//

import Foundation

/// One named dashboard: a stable id, a user-facing name, and its own layout.
nonisolated struct DashboardRecord: Identifiable, Equatable, Sendable, Codable {

    let id: UUID
    var name: String
    var layout: DashboardLayout

    init(id: UUID = UUID(), name: String, layout: DashboardLayout) {
        self.id = id
        self.name = name
        self.layout = layout
    }
}

/// An ordered collection of dashboards plus which one is active.
nonisolated struct DashboardCollection: Equatable, Sendable, Codable {

    /// The dashboards, in display order. Non-empty (see file notes).
    private(set) var dashboards: [DashboardRecord]

    /// The id of the dashboard currently shown / edited. Always one of `dashboards`.
    private(set) var activeID: UUID

    init(dashboards: [DashboardRecord], activeID: UUID) {
        precondition(!dashboards.isEmpty, "DashboardCollection needs at least one dashboard")
        self.dashboards = dashboards
        self.activeID = dashboards.contains { $0.id == activeID } ? activeID : dashboards[0].id
    }

    /// A collection with a single dashboard.
    init(single record: DashboardRecord) {
        self.init(dashboards: [record], activeID: record.id)
    }

    // MARK: - Reads

    /// The active dashboard. Total — falls back to the first if `activeID` ever
    /// drifts (it shouldn't; the invariant is enforced on load + mutation).
    var active: DashboardRecord {
        dashboards.first { $0.id == activeID } ?? dashboards[0]
    }

    var activeLayout: DashboardLayout { active.layout }

    var count: Int { dashboards.count }

    /// Whether `id` names a dashboard in this collection.
    func contains(_ id: UUID) -> Bool {
        dashboards.contains { $0.id == id }
    }

    // MARK: - Mutations (pure — each keeps the invariants)

    /// Make `id` the active dashboard. No-op if `id` isn't in the collection.
    mutating func select(_ id: UUID) {
        guard contains(id) else { return }
        activeID = id
    }

    /// Replace the active dashboard's layout.
    mutating func setActiveLayout(_ layout: DashboardLayout) {
        guard let index = dashboards.firstIndex(where: { $0.id == activeID }) else { return }
        dashboards[index].layout = layout
    }

    /// Add a dashboard and make it active. Returns its new id.
    @discardableResult
    mutating func addDashboard(name: String, layout: DashboardLayout) -> UUID {
        let record = DashboardRecord(name: name, layout: layout)
        dashboards.append(record)
        activeID = record.id
        return record.id
    }

    /// Remove the dashboard with `id`. Refused (`false`) when it is the last one.
    /// If the removed dashboard was active, the dashboard that slides into its
    /// slot becomes active (or the new last one) — deterministic.
    @discardableResult
    mutating func removeDashboard(_ id: UUID) -> Bool {
        guard dashboards.count > 1,
              let index = dashboards.firstIndex(where: { $0.id == id })
        else { return false }

        let wasActive = (activeID == id)
        dashboards.remove(at: index)
        if wasActive {
            let newIndex = min(index, dashboards.count - 1)
            activeID = dashboards[newIndex].id
        }
        return true
    }

    /// Rename the dashboard with `id`. Trims whitespace; ignores an empty name.
    mutating func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = dashboards.firstIndex(where: { $0.id == id })
        else { return }
        dashboards[index].name = trimmed
    }

    // MARK: - Structural validity (for the store's load gate)

    /// Whether the collection is well-formed: non-empty, unique dashboard ids,
    /// `activeID` present, and every layout structurally valid on `grid`.
    func isStructurallyValid(grid: DashboardGrid) -> Bool {
        guard !dashboards.isEmpty else { return false }
        let ids = dashboards.map(\.id)
        guard Set(ids).count == ids.count else { return false }
        guard ids.contains(activeID) else { return false }
        return dashboards.allSatisfy {
            DashboardLayoutValidator.isStructurallyValid($0.layout, grid: grid)
        }
    }
}
