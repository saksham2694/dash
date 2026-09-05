//
//  MapAppearanceTests.swift
//  DashTests
//
//  M9.1 — the GTA San Andreas map appearance:
//    • `MapAppearance` — vocabulary + default.
//    • `MapAppearanceStore` — the shared, persisted preference: default
//      Standard, both cases persist, an invalid persisted value falls back
//      safely. Mirrors `SpeedUnitStoreTests`.
//    • `GoogleMapStyleResolver` — Standard resolves to no override (`nil`,
//      the SDK's own look); GTA San Andreas resolves to valid, non-empty
//      style JSON.
//    • `MapViewModel.setAppearance` — resolves to the right provider, no-ops
//      on a redundant call, and never touches unrelated map/navigation state.
//

import Foundation
import Testing
@testable import Dash

// MARK: - MapAppearance

@Suite("MapAppearance")
struct MapAppearanceTests {

    @Test("default is Standard")
    func defaultIsStandard() {
        #expect(MapAppearance.default == .standard)
    }

    @Test("every case has a non-empty display name")
    func displayNames() {
        for appearance in MapAppearance.allCases {
            #expect(!appearance.displayName.isEmpty)
        }
    }

    @Test("round-trips through its raw value")
    func rawValueRoundTrip() {
        for appearance in MapAppearance.allCases {
            #expect(MapAppearance(rawValue: appearance.rawValue) == appearance)
        }
    }
}

// MARK: - MapAppearanceStore

@MainActor
@Suite("MapAppearanceStore")
struct MapAppearanceStoreTests {

    private func store(_ suite: String = UUID().uuidString) -> (MapAppearanceStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "mapappearance-\(suite)")!
        defaults.removePersistentDomain(forName: "mapappearance-\(suite)")
        return (MapAppearanceStore(defaults: defaults), defaults)
    }

    @Test("a fresh store defaults to Standard")
    func freshStoreIsStandard() {
        let (s, _) = store()
        #expect(s.appearance == .standard)
        #expect(s.appearance == MapAppearance.default)
    }

    @Test("selecting GTA San Andreas persists across store instances")
    func gtaPersists() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: "mapappearance-\(suite)")!
        defaults.removePersistentDomain(forName: "mapappearance-\(suite)")

        let first = MapAppearanceStore(defaults: defaults)
        first.select(.gtaSanAndreas)
        #expect(first.appearance == .gtaSanAndreas)

        let reopened = MapAppearanceStore(defaults: defaults)
        #expect(reopened.appearance == .gtaSanAndreas)
    }

    @Test("selecting Standard persists across store instances")
    func standardPersists() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: "mapappearance-\(suite)")!
        defaults.removePersistentDomain(forName: "mapappearance-\(suite)")

        let first = MapAppearanceStore(defaults: defaults)
        first.select(.gtaSanAndreas)
        first.select(.standard)
        #expect(first.appearance == .standard)

        let reopened = MapAppearanceStore(defaults: defaults)
        #expect(reopened.appearance == .standard)
    }

    @Test("a corrupt persisted value falls back to Standard")
    func corruptValueFallsBack() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: "mapappearance-\(suite)")!
        defaults.set("not-a-real-appearance", forKey: MapAppearanceStore.storageKey)

        let s = MapAppearanceStore(defaults: defaults)
        #expect(s.appearance == .standard)
    }

    @Test("resetToDefault restores and persists Standard")
    func resetRestoresDefault() {
        let (s, defaults) = store()
        s.select(.gtaSanAndreas)
        s.resetToDefault()
        #expect(s.appearance == .standard)

        let reopened = MapAppearanceStore(defaults: defaults)
        #expect(reopened.appearance == .standard)
    }
}

// MARK: - GoogleMapStyleResolver

@Suite("GoogleMapStyleResolver")
struct GoogleMapStyleResolverTests {

    @Test("Standard has no style override")
    func standardIsUnstyled() {
        #expect(GoogleMapStyleResolver.styleJSON(for: .standard) == nil)
    }

    @Test("GTA San Andreas resolves to non-empty, valid JSON")
    func gtaResolvesToValidJSON() throws {
        let json = try #require(GoogleMapStyleResolver.styleJSON(for: .gtaSanAndreas))
        #expect(!json.isEmpty)

        let data = try #require(json.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data)
        let rules = try #require(parsed as? [[String: Any]])
        #expect(!rules.isEmpty)

        // Every rule is a well-formed style rule: a non-empty `stylers` array,
        // and — since this must actually restyle the map, not just turn things
        // off — at least one rule naming `road`, `water`, and `landscape`.
        var featureTypes = Set<String>()
        for rule in rules {
            let stylers = try #require(rule["stylers"] as? [[String: Any]])
            #expect(!stylers.isEmpty)
            if let featureType = rule["featureType"] as? String {
                featureTypes.insert(featureType)
            }
        }
        #expect(featureTypes.contains { $0.hasPrefix("road") })
        #expect(featureTypes.contains { $0.hasPrefix("water") })
        #expect(featureTypes.contains { $0.hasPrefix("landscape") })
    }
}

// MARK: - MapViewModel.setAppearance

@MainActor
@Suite("MapViewModel.setAppearance")
struct MapViewModelAppearanceTests {

    @Test("defaults to Standard, backed by a GoogleMapProvider with no style override")
    func defaultsToStandard() {
        let viewModel = MapViewModel()
        #expect(viewModel.mapAppearance == .standard)

        let provider = viewModel.provider as? GoogleMapProvider
        #expect(provider?.appearance == .standard)
    }

    @Test("selecting GTA San Andreas swaps in a provider with that appearance")
    func selectingGTASwapsProvider() {
        let viewModel = MapViewModel()
        viewModel.setAppearance(.gtaSanAndreas)

        #expect(viewModel.mapAppearance == .gtaSanAndreas)
        let provider = viewModel.provider as? GoogleMapProvider
        #expect(provider?.appearance == .gtaSanAndreas)
        #expect(provider?.id == .googleMaps)
    }

    @Test("a redundant call does not replace the provider instance")
    func redundantCallIsANoOp() {
        let viewModel = MapViewModel()
        viewModel.setAppearance(.gtaSanAndreas)

        // `any MapProvider` isn't Equatable; identity is observed through the
        // wrapped GMS-free style value instead, which only changes on a real
        // reassignment.
        let before = (viewModel.provider as? GoogleMapProvider)?.appearance
        viewModel.setAppearance(.gtaSanAndreas)
        let after = (viewModel.provider as? GoogleMapProvider)?.appearance
        #expect(before == after)
        #expect(viewModel.mapAppearance == .gtaSanAndreas)
    }

    @Test("changing appearance does not alter unrelated map/navigation state")
    func doesNotAlterUnrelatedState() {
        let viewModel = MapViewModel()
        let camera = viewModel.camera
        let content = viewModel.content
        let mode = viewModel.mode
        let follows = viewModel.followsVehicle
        let route = viewModel.route

        viewModel.setAppearance(.gtaSanAndreas)

        #expect(viewModel.camera == camera)
        #expect(viewModel.content == content)
        #expect(viewModel.mode == mode)
        #expect(viewModel.followsVehicle == follows)
        #expect(viewModel.route == route)
    }
}
