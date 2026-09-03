//
//  DashboardLayoutStoreTests.swift
//  DashTests
//
//  `DashboardLayoutStore` (M5.2.0): default seeding, `UserDefaults` round-trip,
//  schema-version handling, and safe fallback on corrupt / invalid data. Plus a
//  small `DashboardSpaceView` page-clamp check.
//

import Foundation
import Testing
@testable import Dash

@MainActor
@Suite("DashboardLayoutStore")
struct DashboardLayoutStoreTests {

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "dash-layout-\(UUID().uuidString)")!
    }

    // Stored (not computed): placement / page identity is part of `Equatable`,
    // so every comparison in a test must use the *same* layout value.
    private let seed = DashboardLayout.starter(featureID: "maps")

    /// A different, structurally-valid one-page layout.
    private let altLayout = DashboardLayout(pages: [
        DashboardPage(placements: [
            WidgetPlacement(featureID: "maps", size: .medium, origin: GridPoint(column: 0, row: 0)),
        ])
    ])

    @Test("uses the seed when nothing is persisted")
    func defaultsToSeed() {
        let store = DashboardLayoutStore(seed: seed, defaults: ephemeralDefaults())
        #expect(store.layout == seed)
    }

    @Test("a replaced layout persists and reloads")
    func persistenceRoundTrip() {
        let defaults = ephemeralDefaults()

        let store = DashboardLayoutStore(seed: seed, defaults: defaults)
        store.replace(with: altLayout)
        #expect(store.layout == altLayout)

        let reloaded = DashboardLayoutStore(seed: seed, defaults: defaults)
        #expect(reloaded.layout == altLayout)
    }

    @Test("resetToDefault restores and persists the seed")
    func reset() {
        let defaults = ephemeralDefaults()
        let store = DashboardLayoutStore(seed: seed, defaults: defaults)
        store.replace(with: altLayout)

        store.resetToDefault()
        #expect(store.layout == seed)
        #expect(DashboardLayoutStore(seed: seed, defaults: defaults).layout == seed)
    }

    @Test("undecodable persisted data falls back to the seed")
    func corruptDataFallsBack() {
        let defaults = ephemeralDefaults()
        defaults.set(Data([0x00, 0x01, 0x02, 0xFF]), forKey: DashboardLayoutStore.storageKey)

        let store = DashboardLayoutStore(seed: seed, defaults: defaults)
        #expect(store.layout == seed)
    }

    @Test("an unrecognised schema version falls back to the seed")
    func wrongSchemaVersionFallsBack() throws {
        let defaults = ephemeralDefaults()
        let layoutJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(altLayout))
        let envelope = try JSONSerialization.data(withJSONObject: ["version": 999, "layout": layoutJSON])
        defaults.set(envelope, forKey: DashboardLayoutStore.storageKey)

        let store = DashboardLayoutStore(seed: seed, defaults: defaults)
        #expect(store.layout == seed)
    }

    @Test("a persisted-but-structurally-invalid layout falls back to the seed")
    func invalidPersistedLayoutFallsBack() {
        let defaults = ephemeralDefaults()

        // Two overlapping compacts — replace() persists whatever it is given…
        let overlapping = DashboardLayout(pages: [
            DashboardPage(placements: [
                WidgetPlacement(featureID: "maps", size: .compact, origin: GridPoint(column: 0, row: 0)),
                WidgetPlacement(featureID: "maps", size: .compact, origin: GridPoint(column: 1, row: 0)),
            ])
        ])
        DashboardLayoutStore(seed: seed, defaults: defaults).replace(with: overlapping)

        // …but load rejects it.
        #expect(DashboardLayoutStore(seed: seed, defaults: defaults).layout == seed)
    }

    @Test("the storage key and schema version are the documented constants")
    func constants() {
        #expect(DashboardLayoutStore.storageKey == "shell.dashboardLayout.v1")
        #expect(DashboardLayoutStore.schemaVersion == 1)
    }
}

@MainActor
@Suite("DashboardSpaceView")
struct DashboardSpaceViewTests {

    @Test("renders the single Dashboard page and is feature-agnostic")
    func rendersTheOnePage() {
        let store = DashboardLayoutStore(
            seed: .starter(featureID: "maps"),
            defaults: UserDefaults(suiteName: "dash-space-\(UUID().uuidString)")!
        )
        let view = DashboardSpaceView(
            layoutStore: store, editModel: DashboardEditModel(),
            registry: FeatureRegistry.makeDefault(), grid: .standard,
            onOpenFeature: { _ in }
        )

        #expect(view.page?.id == store.layout.pages.first?.id)
        #expect(view.page?.placements.isEmpty == false)
    }
}
