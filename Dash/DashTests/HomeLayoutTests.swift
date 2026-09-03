//
//  HomeLayoutTests.swift
//  DashTests
//
//  M5.3.0 — the App-Home launcher foundation: the SDK-neutral model
//  (`HomeLayout` / `HomePage` / `HomeAppPlacement`) and `HomeLayoutStore`
//  persistence. Mirrors the M5.2.0 Dashboard-layout tests.
//

import Foundation
import Testing
@testable import Dash

// MARK: - Model

@Suite("HomeLayout model")
struct HomeLayoutModelTests {

    @Test("a placement gets a unique id by default; an explicit id is kept")
    func placementIdentity() {
        let a = HomeAppPlacement(featureID: "maps")
        let b = HomeAppPlacement(featureID: "maps")
        #expect(a.id != b.id)

        let fixed = UUID()
        #expect(HomeAppPlacement(id: fixed, featureID: "maps").id == fixed)
    }

    @Test("paginate splits the feature ids across pages, in order, filling each first")
    func paginateSplitsInOrder() {
        let layout = HomeLayout.paginate(featureIDs: ["a", "b", "c", "d", "e"], capacity: 2)
        #expect(layout.pageCount == 3)
        #expect(layout.page(at: 0)?.apps.map(\.featureID) == ["a", "b"])
        #expect(layout.page(at: 1)?.apps.map(\.featureID) == ["c", "d"])
        #expect(layout.page(at: 2)?.apps.map(\.featureID) == ["e"])
        #expect(layout.allApps.count == 5)
        // No empty pages.
        #expect(layout.pages.allSatisfy { !$0.apps.isEmpty })
    }

    @Test("capacity drives the page count: 5 / 10 / 17 apps at capacity 8")
    func paginateCapacityExamples() {
        func ids(_ n: Int) -> [FeatureID] { (0..<n).map { "app-\($0)" } }
        #expect(HomeLayout.paginate(featureIDs: ids(5), capacity: 8).pageCount == 1)
        #expect(HomeLayout.paginate(featureIDs: ids(10), capacity: 8).pageCount == 2)
        #expect(HomeLayout.paginate(featureIDs: ids(17), capacity: 8).pageCount == 3)
    }

    @Test("one real app is a single Home page at the default capacity")
    func paginateSingleApp() {
        let layout = HomeLayout.paginate(featureIDs: ["maps"])
        #expect(layout.pageCount == 1)
        #expect(layout.page(at: 0)?.apps.map(\.featureID) == ["maps"])
    }

    @Test("a full page adds no extra page; one more app adds exactly one page")
    func paginateGrowsByOnePage() {
        func ids(_ n: Int) -> [FeatureID] { (0..<n).map { "app-\($0)" } }
        let cap = HomeGrid.capacity
        #expect(HomeLayout.paginate(featureIDs: ids(cap)).pageCount == 1)
        #expect(HomeLayout.paginate(featureIDs: ids(cap + 1)).pageCount == 2)
        #expect(HomeLayout.paginate(featureIDs: ids(cap * 2)).pageCount == 2)
        #expect(HomeLayout.paginate(featureIDs: ids(cap * 2 + 1)).pageCount == 3)
    }

    @Test("paginate with no features is one empty page")
    func paginateEmpty() {
        let layout = HomeLayout.paginate(featureIDs: [])
        #expect(layout.pageCount == 1)
        #expect(layout.isEmpty)
    }

    @Test("page access is bounds-checked and page index is clamped")
    func pageHandling() {
        let layout = HomeLayout.paginate(featureIDs: ["a", "b", "c"], capacity: 1)
        #expect(layout.pageCount == 3)
        #expect(layout.page(at: 1) != nil)
        #expect(layout.page(at: 3) == nil)
        #expect(layout.page(at: -1) == nil)

        #expect(layout.clampedPageIndex(-5) == 0)
        #expect(layout.clampedPageIndex(0) == 0)
        #expect(layout.clampedPageIndex(2) == 2)
        #expect(layout.clampedPageIndex(99) == 2)

        #expect(HomeLayout(pages: []).clampedPageIndex(3) == 0)
    }

    @Test("round-trips through Codable with identity preserved")
    func codableRoundTrip() throws {
        let original = HomeLayout.paginate(featureIDs: ["maps", "music", "speedometer"], capacity: 2)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HomeLayout.self, from: data)

        #expect(decoded == original)
        #expect(decoded.allApps.map(\.id) == original.allApps.map(\.id))
        #expect(decoded.pages.map(\.id) == original.pages.map(\.id))
    }
}

// MARK: - Store

@MainActor
@Suite("HomeLayoutStore")
struct HomeLayoutStoreTests {

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "dash-home-\(UUID().uuidString)")!
    }

    private let seed = HomeLayout.paginate(featureIDs: ["maps"])
    private let altLayout = HomeLayout(pages: [
        HomePage(apps: [HomeAppPlacement(featureID: "maps"), HomeAppPlacement(featureID: "music")]),
    ])

    @Test("uses the seed when nothing is persisted")
    func defaultsToSeed() {
        let store = HomeLayoutStore(seed: seed, defaults: ephemeralDefaults())
        #expect(store.layout == seed)
    }

    @Test("a replaced layout persists and reloads with stable ids")
    func persistenceRoundTrip() {
        let defaults = ephemeralDefaults()

        let store = HomeLayoutStore(seed: seed, defaults: defaults)
        store.replace(with: altLayout)
        #expect(store.layout == altLayout)

        let reloaded = HomeLayoutStore(seed: seed, defaults: defaults)
        #expect(reloaded.layout == altLayout)
        #expect(reloaded.layout.allApps.map(\.id) == altLayout.allApps.map(\.id))
    }

    @Test("resetToDefault restores and persists the seed")
    func reset() {
        let defaults = ephemeralDefaults()
        let store = HomeLayoutStore(seed: seed, defaults: defaults)
        store.replace(with: altLayout)

        store.resetToDefault()
        #expect(store.layout == seed)
        #expect(HomeLayoutStore(seed: seed, defaults: defaults).layout == seed)
    }

    @Test("undecodable persisted data falls back to the seed")
    func corruptDataFallsBack() {
        let defaults = ephemeralDefaults()
        defaults.set(Data([0x00, 0x01, 0xFF, 0x7F]), forKey: HomeLayoutStore.storageKey)
        #expect(HomeLayoutStore(seed: seed, defaults: defaults).layout == seed)
    }

    @Test("an unrecognised schema version falls back to the seed")
    func wrongSchemaVersionFallsBack() throws {
        let defaults = ephemeralDefaults()
        let layoutJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(altLayout))
        let envelope = try JSONSerialization.data(withJSONObject: ["version": 42, "layout": layoutJSON])
        defaults.set(envelope, forKey: HomeLayoutStore.storageKey)
        #expect(HomeLayoutStore(seed: seed, defaults: defaults).layout == seed)
    }

    @Test("a persisted layout with duplicate placement ids falls back to the seed")
    func duplicateIDsFallBack() throws {
        let defaults = ephemeralDefaults()
        let shared = UUID()
        let broken = HomeLayout(pages: [HomePage(apps: [
            HomeAppPlacement(id: shared, featureID: "maps"),
            HomeAppPlacement(id: shared, featureID: "music"),
        ])])
        let layoutJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(broken))
        let envelope = try JSONSerialization.data(withJSONObject: ["version": 1, "layout": layoutJSON])
        defaults.set(envelope, forKey: HomeLayoutStore.storageKey)
        #expect(HomeLayoutStore(seed: seed, defaults: defaults).layout == seed)
    }

    @Test("the storage key and schema version are the documented constants")
    func constants() {
        #expect(HomeLayoutStore.storageKey == "shell.homeLayout.v1")
        #expect(HomeLayoutStore.schemaVersion == 1)
    }
}
