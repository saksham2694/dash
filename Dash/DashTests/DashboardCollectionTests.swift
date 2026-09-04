//
//  DashboardCollectionTests.swift
//  DashTests
//
//  The `DashboardCollection` value type + the collection-management surface of
//  `DashboardCollectionStore` (M5.6): add, select, remove, rename, independent
//  per-dashboard layouts, the "never zero dashboards" rule, and deterministic
//  re-selection when the active dashboard is removed.
//

import Foundation
import Testing
@testable import Dash

// MARK: - Pure value type

@Suite("DashboardCollection value type")
struct DashboardCollectionValueTests {

    private func record(_ name: String, _ layout: DashboardLayout = DashboardLayout(pages: [DashboardPage()])) -> DashboardRecord {
        DashboardRecord(name: name, layout: layout)
    }

    @Test("a single-dashboard collection is active on that dashboard")
    func singleActive() {
        let r = record("A")
        let c = DashboardCollection(single: r)
        #expect(c.count == 1)
        #expect(c.activeID == r.id)
        #expect(c.active == r)
    }

    @Test("an out-of-range activeID clamps to the first dashboard")
    func activeIDClamps() {
        let a = record("A"), b = record("B")
        let c = DashboardCollection(dashboards: [a, b], activeID: UUID())
        #expect(c.activeID == a.id)
    }

    @Test("adding a dashboard appends it and makes it active")
    func add() {
        var c = DashboardCollection(single: record("A"))
        let id = c.addDashboard(name: "B", layout: DashboardLayout(pages: [DashboardPage()]))
        #expect(c.count == 2)
        #expect(c.activeID == id)
        #expect(c.dashboards.last?.name == "B")
    }

    @Test("select switches the active dashboard; unknown id is a no-op")
    func select() {
        let a = record("A"), b = record("B")
        var c = DashboardCollection(dashboards: [a, b], activeID: a.id)
        c.select(b.id)
        #expect(c.activeID == b.id)
        c.select(UUID())
        #expect(c.activeID == b.id)
    }

    @Test("the last dashboard can never be removed")
    func cannotRemoveLast() {
        var c = DashboardCollection(single: record("A"))
        let removed = c.removeDashboard(c.activeID)
        #expect(removed == false)
        #expect(c.count == 1)
    }

    @Test("removing the active dashboard selects the one that slides into its slot")
    func removeActiveReselectsDeterministically() {
        let a = record("A"), b = record("B"), d = record("D")
        var c = DashboardCollection(dashboards: [a, b, d], activeID: b.id)
        let removed = c.removeDashboard(b.id)
        #expect(removed)
        // b was at index 1; the dashboard now at index 1 is `d`.
        #expect(c.activeID == d.id)
        #expect(c.dashboards.map(\.name) == ["A", "D"])
    }

    @Test("removing the active last dashboard falls back to the new last")
    func removeActiveLastReselects() {
        let a = record("A"), b = record("B")
        var c = DashboardCollection(dashboards: [a, b], activeID: b.id)
        let removed = c.removeDashboard(b.id)
        #expect(removed)
        #expect(c.activeID == a.id)
    }

    @Test("removing a non-active dashboard leaves the active one alone")
    func removeNonActive() {
        let a = record("A"), b = record("B")
        var c = DashboardCollection(dashboards: [a, b], activeID: a.id)
        let removed = c.removeDashboard(b.id)
        #expect(removed)
        #expect(c.activeID == a.id)
        #expect(c.count == 1)
    }

    @Test("rename trims whitespace and ignores an empty name")
    func rename() {
        let a = record("A")
        var c = DashboardCollection(single: a)
        c.rename(a.id, to: "  Road Trip  ")
        #expect(c.dashboards.first?.name == "Road Trip")
        c.rename(a.id, to: "   ")
        #expect(c.dashboards.first?.name == "Road Trip")
    }

    @Test("setActiveLayout only touches the active dashboard")
    func setActiveLayoutIsScoped() {
        let a = record("A"), b = record("B")
        var c = DashboardCollection(dashboards: [a, b], activeID: a.id)
        let newLayout = DashboardLayout.starter(featureID: "maps")
        c.setActiveLayout(newLayout)
        #expect(c.dashboards[0].layout == newLayout)
        #expect(c.dashboards[1].layout == b.layout)
    }
}

// MARK: - Store collection management

@MainActor
@Suite("DashboardCollectionStore — collection management")
struct DashboardCollectionStoreManagementTests {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "dash-mgmt-\(UUID().uuidString)")!
    }

    private func store(_ d: UserDefaults) -> DashboardCollectionStore {
        DashboardCollectionStore(seed: .starter(featureID: "maps"), defaults: d)
    }

    @Test("fresh state has exactly one dashboard")
    func freshIsOne() {
        #expect(store(defaults()).dashboardCount == 1)
    }

    @Test("added dashboards are independent — editing one never touches another")
    func independentLayouts() {
        let d = defaults()
        let s = store(d)
        let firstID = s.activeID
        #expect(s.layout.allPlacements.count == 3)   // the seeded starter

        let secondID = s.addDashboard(name: "Trip")
        #expect(s.activeID == secondID)
        #expect(s.layout.allPlacements.isEmpty)      // a new dashboard starts empty

        // Add a widget to the second dashboard only.
        #expect(s.addWidget(featureID: "maps", size: .medium) == .added(s.layout.allPlacements.first!.id))
        #expect(s.layout.allPlacements.count == 1)

        // Switch back — the first dashboard's layout is intact.
        s.select(id: firstID)
        #expect(s.layout.allPlacements.count == 3)

        // …and forward again — the second's edit persisted.
        s.select(id: secondID)
        #expect(s.layout.allPlacements.count == 1)
    }

    @Test("the collection, names and active id survive a reload")
    func collectionPersistsRoundTrip() {
        let d = defaults()
        let s = store(d)
        let tripID = s.addDashboard(name: "Trip")
        s.renameDashboard(id: s.collection.dashboards[0].id, to: "Home")

        let reloaded = store(d)
        #expect(reloaded.dashboardCount == 2)
        #expect(reloaded.activeID == tripID)
        #expect(reloaded.collection.dashboards.map(\.name) == ["Home", "Trip"])
    }

    @Test("removing the last dashboard is refused")
    func cannotRemoveFinal() {
        let s = store(defaults())
        #expect(s.removeDashboard(id: s.activeID) == false)
        #expect(s.dashboardCount == 1)
    }

    @Test("removing the active dashboard selects a valid remaining one and persists")
    func removeActivePersists() {
        let d = defaults()
        let s = store(d)
        let firstID = s.activeID
        let secondID = s.addDashboard(name: "Trip")   // now active

        #expect(s.removeDashboard(id: secondID))
        #expect(s.activeID == firstID)
        #expect(s.dashboardCount == 1)

        let reloaded = store(d)
        #expect(reloaded.dashboardCount == 1)
        #expect(reloaded.activeID == firstID)
    }

    @Test("auto-named dashboards read 'Dashboard', 'Dashboard 2', …")
    func autoNames() {
        let s = store(defaults())
        #expect(s.activeName == "Dashboard")
        s.addDashboard()
        #expect(s.activeName == "Dashboard 2")
        s.addDashboard()
        #expect(s.activeName == "Dashboard 3")
    }

    @Test("selecting an unknown id does nothing")
    func selectUnknown() {
        let s = store(defaults())
        let before = s.activeID
        s.select(id: UUID())
        #expect(s.activeID == before)
    }
}
