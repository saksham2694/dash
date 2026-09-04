//
//  DashboardCollectionStoreTests.swift
//  DashTests
//
//  `DashboardCollectionStore` (M5.6) — the single-dashboard behaviour it
//  inherits from the retired `DashboardLayoutStore` (seed, round-trip, safe
//  fallback) plus the collection behaviour: one dashboard by default, add /
//  select / remove / rename, independent layouts, and clean migration from the
//  legacy single-dashboard key.
//
//  The pure collection value type is exercised in `DashboardCollectionTests`.
//

import Foundation
import Testing
@testable import Dash

@MainActor
@Suite("DashboardCollectionStore — single dashboard")
struct DashboardCollectionStoreSingleTests {

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "dash-collection-\(UUID().uuidString)")!
    }

    private let seed = DashboardLayout.starter(featureID: "maps")

    private let altLayout = DashboardLayout(pages: [
        DashboardPage(placements: [
            WidgetPlacement(featureID: "maps", size: .medium, origin: GridPoint(column: 0, row: 0)),
        ])
    ])

    @Test("a fresh store has exactly one dashboard, seeded")
    func freshIsOneSeededDashboard() {
        let store = DashboardCollectionStore(seed: seed, defaults: ephemeralDefaults())
        #expect(store.dashboardCount == 1)
        #expect(store.layout == seed)
        #expect(store.activeName == DashboardCollectionStore.firstDashboardName)
    }

    @Test("a replaced active layout persists and reloads")
    func persistenceRoundTrip() {
        let defaults = ephemeralDefaults()

        let store = DashboardCollectionStore(seed: seed, defaults: defaults)
        store.replace(with: altLayout)
        #expect(store.layout == altLayout)

        let reloaded = DashboardCollectionStore(seed: seed, defaults: defaults)
        #expect(reloaded.layout == altLayout)
        #expect(reloaded.dashboardCount == 1)
    }

    @Test("resetToDefault restores and persists the seed for the active dashboard")
    func reset() {
        let defaults = ephemeralDefaults()
        let store = DashboardCollectionStore(seed: seed, defaults: defaults)
        store.replace(with: altLayout)

        store.resetToDefault()
        #expect(store.layout == seed)
        #expect(DashboardCollectionStore(seed: seed, defaults: defaults).layout == seed)
    }

    @Test("undecodable persisted data falls back to a fresh single dashboard")
    func corruptDataFallsBack() {
        let defaults = ephemeralDefaults()
        defaults.set(Data([0x00, 0x01, 0x02, 0xFF]), forKey: DashboardCollectionStore.storageKey)

        let store = DashboardCollectionStore(seed: seed, defaults: defaults)
        #expect(store.dashboardCount == 1)
        #expect(store.layout == seed)
    }

    @Test("an unrecognised schema version falls back")
    func wrongSchemaVersionFallsBack() throws {
        let defaults = ephemeralDefaults()
        let collection = DashboardCollection(single: DashboardRecord(name: "X", layout: altLayout))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(collection))
        let envelope = try JSONSerialization.data(withJSONObject: ["version": 999, "collection": json])
        defaults.set(envelope, forKey: DashboardCollectionStore.storageKey)

        #expect(DashboardCollectionStore(seed: seed, defaults: defaults).layout == seed)
    }

    @Test("a structurally invalid persisted collection falls back")
    func invalidPersistedCollectionFallsBack() throws {
        let defaults = ephemeralDefaults()
        let overlapping = DashboardLayout(pages: [DashboardPage(placements: [
            WidgetPlacement(featureID: "maps", size: .compact, origin: GridPoint(column: 0, row: 0)),
            WidgetPlacement(featureID: "maps", size: .compact, origin: GridPoint(column: 0, row: 1)),
        ])])
        let collection = DashboardCollection(single: DashboardRecord(name: "Bad", layout: overlapping))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(collection))
        let envelope = try JSONSerialization.data(withJSONObject: ["version": 1, "collection": json])
        defaults.set(envelope, forKey: DashboardCollectionStore.storageKey)

        #expect(DashboardCollectionStore(seed: seed, defaults: defaults).layout == seed)
    }

    @Test("the storage key and schema version are the documented constants")
    func constants() {
        #expect(DashboardCollectionStore.storageKey == "shell.dashboards.v1")
        #expect(DashboardCollectionStore.legacyStorageKey == "shell.dashboardLayout.v2")
        #expect(DashboardCollectionStore.schemaVersion == 1)
    }
}

// MARK: - Migration

@MainActor
@Suite("DashboardCollectionStore — migration from the single-dashboard format")
struct DashboardCollectionStoreMigrationTests {

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "dash-migrate-\(UUID().uuidString)")!
    }

    private let seed = DashboardLayout.starter(featureID: "maps")

    /// Write a legacy `{version:1, layout:…}` envelope under the old key.
    private func writeLegacy(_ layout: DashboardLayout, to defaults: UserDefaults) throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(layout))
        let envelope = try JSONSerialization.data(withJSONObject: ["version": 1, "layout": json])
        defaults.set(envelope, forKey: DashboardCollectionStore.legacyStorageKey)
    }

    @Test("an existing single-dashboard layout becomes exactly one dashboard, unchanged")
    func migratesToOneDashboard() throws {
        let defaults = ephemeralDefaults()
        let existing = DashboardLayout(pages: [DashboardPage(placements: [
            WidgetPlacement(featureID: "maps", size: .large, origin: GridPoint(column: 0, row: 0)),
            WidgetPlacement(featureID: "maps", size: .compact, origin: GridPoint(column: 1, row: 0)),
        ])])
        try writeLegacy(existing, to: defaults)

        let store = DashboardCollectionStore(seed: seed, defaults: defaults)
        #expect(store.dashboardCount == 1)
        #expect(store.layout == existing)            // all customization preserved
        #expect(store.activeName == DashboardCollectionStore.firstDashboardName)
    }

    @Test("migration persists the new format and removes the legacy key")
    func migrationPersistsAndClearsLegacy() throws {
        let defaults = ephemeralDefaults()
        let existing = DashboardLayout(pages: [DashboardPage(placements: [
            WidgetPlacement(featureID: "maps", size: .medium, origin: GridPoint(column: 0, row: 0)),
        ])])
        try writeLegacy(existing, to: defaults)

        _ = DashboardCollectionStore(seed: seed, defaults: defaults)

        #expect(defaults.data(forKey: DashboardCollectionStore.storageKey) != nil)
        #expect(defaults.data(forKey: DashboardCollectionStore.legacyStorageKey) == nil)
    }

    @Test("relaunch after migration does not duplicate the dashboard")
    func noDuplicateOnRelaunch() throws {
        let defaults = ephemeralDefaults()
        let existing = DashboardLayout(pages: [DashboardPage(placements: [
            WidgetPlacement(featureID: "maps", size: .large, origin: GridPoint(column: 0, row: 0)),
        ])])
        try writeLegacy(existing, to: defaults)

        _ = DashboardCollectionStore(seed: seed, defaults: defaults)   // migrates
        let relaunch1 = DashboardCollectionStore(seed: seed, defaults: defaults)
        let relaunch2 = DashboardCollectionStore(seed: seed, defaults: defaults)

        #expect(relaunch1.dashboardCount == 1)
        #expect(relaunch2.dashboardCount == 1)
        #expect(relaunch2.layout == existing)
    }

    @Test("a legacy layout invalid on the current grid is not migrated — a fresh dashboard is seeded")
    func invalidLegacyLayoutSeedsFresh() throws {
        let defaults = ephemeralDefaults()
        // Column 3 — off the 2-column grid.
        let oldGridLayout = DashboardLayout(pages: [DashboardPage(placements: [
            WidgetPlacement(featureID: "maps", size: .compact, origin: GridPoint(column: 3, row: 2)),
        ])])
        try writeLegacy(oldGridLayout, to: defaults)

        let store = DashboardCollectionStore(seed: seed, defaults: defaults)
        #expect(store.dashboardCount == 1)
        #expect(store.layout == seed)
    }

    @Test("the new format wins over a stale legacy key (no re-migration)")
    func newFormatWinsOverLegacy() throws {
        let defaults = ephemeralDefaults()

        // A real collection with two dashboards already persisted…
        let store = DashboardCollectionStore(seed: seed, defaults: defaults)
        let secondID = store.addDashboard(name: "Trip")
        #expect(store.dashboardCount == 2)

        // …and a stale legacy key hanging around.
        try writeLegacy(DashboardLayout.starter(featureID: "maps"), to: defaults)

        let reloaded = DashboardCollectionStore(seed: seed, defaults: defaults)
        #expect(reloaded.dashboardCount == 2)
        #expect(reloaded.activeID == secondID)
    }
}

// MARK: - DashboardSpaceView still renders the active dashboard

@MainActor
@Suite("DashboardSpaceView")
struct DashboardSpaceViewTests {

    @Test("renders the active dashboard's page and is feature-agnostic")
    func rendersActiveDashboard() {
        let store = DashboardCollectionStore(
            seed: .starter(featureID: "maps"),
            defaults: UserDefaults(suiteName: "dash-space-\(UUID().uuidString)")!
        )
        let view = DashboardSpaceView(
            dashboards: store, editModel: DashboardEditModel(),
            registry: FeatureRegistry.makeDefault(), grid: .standard,
            onOpenFeature: { _ in }
        )

        #expect(view.page?.id == store.layout.pages.first?.id)
        #expect(view.page?.placements.isEmpty == false)
    }
}
