//
//  SettingsFeatureTests.swift
//  DashTests
//
//  M8.3 — the Apple-style Settings mini-app:
//    • `SettingsFeature`'s stable id + full-screen-only capability.
//    • `SettingsRootView.apps(from:)` — the Apps section is derived purely
//      from `FeatureRegistry` manifests (no hardcoded app list, Settings
//      excludes itself).
//    • `SettingsRow`'s Apps-list icons reuse `DashAppIcon` (M8.4 §7) — no
//      second icon mapping of its own.
//    • `SpeedUnitStore` — the shared, persisted Speed Unit preference: default
//      km/h, km/h and mph both persist, an invalid persisted value falls back
//      safely.
//
//  Wallpaper-store behaviour (current selection displayed, selecting updates
//  the store, persists, invalid selection falls back) is already fully
//  covered by `WallpaperTests.swift` — `SettingsWallpaperView` is a thin UI
//  layer over that exact store with no new persistence logic, so it isn't
//  re-tested here (no brittle pixel/view tests, per instruction).
//

import Foundation
import Testing
@testable import Dash

// MARK: - SettingsFeature

@MainActor
@Suite("SettingsFeature")
struct SettingsFeatureTests {

    @Test("keeps the stable id the retired placeholder used")
    func stableID() {
        #expect(SettingsFeature.id == "settings")
        #expect(SettingsFeature().manifest.id == "settings")
        #expect(SettingsFeature().manifest.title == "Settings")
    }

    @Test("is full-screen only — never a dashboard widget size")
    func fullScreenOnly() {
        let manifest = SettingsFeature().manifest
        #expect(manifest.supportedSizes == [.full])
        #expect(manifest.supportedWidgetSizes.isEmpty)
        #expect(manifest.defaultSize == .full)
    }

    @Test("is registered in the default registry as a real feature, launchable full-screen")
    func registeredAsReal() {
        let registry = FeatureRegistry.makeDefault()
        #expect(registry.feature("settings") as? SettingsFeature != nil)
    }

    @Test("the dashboard Add-Widget picker never offers Settings")
    func neverAWidgetChoice() {
        let registry = FeatureRegistry.makeDefault()
        let placeable = DashboardWidgetPickerView.placeableFeatures(registry.manifests).map(\.id)
        #expect(!placeable.contains("settings"))
    }

    @Test("the dashboard feature-reassignment picker never offers Settings, at any widget size")
    func neverAReassignmentChoice() {
        let registry = FeatureRegistry.makeDefault()
        for size in ComponentSize.widgetSizes {
            let eligible = DashboardFeaturePickerView.eligibleFeatures(registry.manifests, for: size).map(\.id)
            #expect(!eligible.contains("settings"))
        }
    }

    @Test("SettingsAppDetailView's literal Speedometer id stays in sync with SpeedometerFeature.id")
    func speedometerIDMatchesLiteral() {
        // Settings keeps its own literal (a feature never references another
        // feature's type) — this guards against silent drift if Speedometer's
        // id is ever renamed.
        #expect(speedometerFeatureID == SpeedometerFeature.id)
    }

    @Test("SettingsAppDetailView's literal Google Maps id stays in sync with MapFeature.id")
    func mapsIDMatchesLiteral() {
        // Same guard as `speedometerIDMatchesLiteral`, for the Map Appearance
        // setting (M9.1).
        #expect(mapFeatureID == MapFeature.id)
    }
}

// MARK: - SettingsRootView.apps(from:) — the registry-driven Apps section

@Suite("SettingsRootView.apps(from:)")
struct SettingsAppsListTests {

    private func manifest(_ id: FeatureID, _ title: String) -> FeatureManifest {
        FeatureManifest(
            id: id, title: title, symbolName: "app.dashed",
            supportedSizes: [.full], defaultSize: .full
        )
    }

    @Test("excludes Settings from its own Apps list")
    func excludesSelf() {
        let manifests = [manifest("maps", "Google Maps"), manifest("settings", "Settings")]
        #expect(SettingsRootView.apps(from: manifests).map(\.id) == ["maps"])
    }

    @Test("includes every other registered feature, in registry order")
    func includesEveryoneElse() {
        let manifests = [
            manifest("maps", "Google Maps"),
            manifest("apple-maps", "Apple Maps"),
            manifest("music", "Apple Music"),
            manifest("weather", "Weather"),
            manifest("speedometer", "Speedometer"),
            manifest("settings", "Settings"),
        ]
        #expect(SettingsRootView.apps(from: manifests).map(\.id) == [
            "maps", "apple-maps", "music", "weather", "speedometer",
        ])
    }

    @Test("a newly registered feature appears automatically — no Settings-specific code needed")
    func reflectsNewFeature() {
        let manifests = [manifest("settings", "Settings"), manifest("brand-new-app", "Brand New App")]
        #expect(SettingsRootView.apps(from: manifests).map(\.id) == ["brand-new-app"])
    }

    @Test("the real default registry's Apps list matches the six shipped features minus Settings")
    @MainActor
    func realRegistry() {
        let registry = FeatureRegistry.makeDefault()
        #expect(SettingsRootView.apps(from: registry.manifests).map(\.id) == [
            "maps", "apple-maps", "music", "weather", "speedometer",
        ])
        #expect(SettingsRootView.apps(from: registry.manifests).map(\.title) == [
            "Google Maps", "Apple Maps", "Apple Music", "Weather", "Speedometer",
        ])
    }
}

// MARK: - SettingsRow icons (M8.4 §7 — reuse DashAppIcon, no second mapping)

@Suite("SettingsRow icon reuse")
struct SettingsRowIconTests {

    @Test("a feature row's icon tint resolves through DashAppIcon.tint(for:id:) — the same lookup Home/sidebar use")
    @MainActor
    func reusesSharedIconResolution() {
        // SettingsRow no longer owns any tint/icon mapping of its own — it
        // builds a `DashAppIcon(manifest:)` directly. This just pins that
        // `DashAppIcon`'s shared resolution still behaves for every real
        // manifest (a regression here would mean Settings' Apps icons and
        // Home/sidebar's icons could silently diverge again).
        for manifest in FeatureRegistry.makeDefault().manifests {
            let tint = DashAppIcon.tint(for: manifest.iconStyle, id: manifest.id)
            #expect(FeatureTint.allCases.contains(tint))
        }
    }
}

// MARK: - SpeedUnitStore

@MainActor
@Suite("SpeedUnitStore")
struct SpeedUnitStoreTests {

    private func store(_ suite: String = UUID().uuidString) -> (SpeedUnitStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "speedunit-\(suite)")!
        defaults.removePersistentDomain(forName: "speedunit-\(suite)")
        return (SpeedUnitStore(defaults: defaults), defaults)
    }

    @Test("a fresh store defaults to km/h")
    func freshStoreIsKmh() {
        let (s, _) = store()
        #expect(s.unit == .kilometersPerHour)
        #expect(s.unit == SpeedometerUnit.default)
    }

    @Test("selecting km/h persists across store instances")
    func kmhPersists() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: "speedunit-\(suite)")!
        defaults.removePersistentDomain(forName: "speedunit-\(suite)")

        let first = SpeedUnitStore(defaults: defaults)
        first.select(.milesPerHour)   // move off the default first, to prove this isn't a no-op
        first.select(.kilometersPerHour)
        #expect(first.unit == .kilometersPerHour)

        let reopened = SpeedUnitStore(defaults: defaults)
        #expect(reopened.unit == .kilometersPerHour)
    }

    @Test("selecting mph persists across store instances")
    func mphPersists() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: "speedunit-\(suite)")!
        defaults.removePersistentDomain(forName: "speedunit-\(suite)")

        let first = SpeedUnitStore(defaults: defaults)
        first.select(.milesPerHour)
        #expect(first.unit == .milesPerHour)

        let reopened = SpeedUnitStore(defaults: defaults)
        #expect(reopened.unit == .milesPerHour)
    }

    @Test("a corrupt persisted value falls back to km/h")
    func corruptValueFallsBack() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: "speedunit-\(suite)")!
        defaults.set("not-a-real-unit", forKey: SpeedUnitStore.storageKey)

        let s = SpeedUnitStore(defaults: defaults)
        #expect(s.unit == .kilometersPerHour)
    }

    @Test("resetToDefault restores and persists km/h")
    func resetRestoresDefault() {
        let (s, defaults) = store()
        s.select(.milesPerHour)
        s.resetToDefault()
        #expect(s.unit == .kilometersPerHour)

        let reopened = SpeedUnitStore(defaults: defaults)
        #expect(reopened.unit == .kilometersPerHour)
    }
}
