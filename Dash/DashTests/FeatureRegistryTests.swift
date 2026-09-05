//
//  FeatureRegistryTests.swift
//  DashTests
//
//  The feature/shell seam (M5.0): `FeatureManifest`, `FeatureRegistry` lookup +
//  duplicate-id detection, and that the default registry registers Map.
//

import Foundation
import SwiftUI
import Testing
@testable import Dash

/// Minimal `DashFeature` for registry tests — no real views.
@MainActor
private final class StubFeature: DashFeature {

    let manifest: FeatureManifest

    init(
        id: FeatureID,
        title: String = "Stub",
        sizes: Set<ComponentSize> = [.large, .full],
        defaultSize: ComponentSize = .large
    ) {
        self.manifest = FeatureManifest(
            id: id,
            title: title,
            symbolName: "app.fill",
            supportedSizes: sizes,
            defaultSize: defaultSize
        )
    }

    func makeFullScreenView() -> AnyView { AnyView(EmptyView()) }
    func makeComponentView(size: ComponentSize) -> AnyView { AnyView(EmptyView()) }
}

@MainActor
@Suite("FeatureRegistry")
struct FeatureRegistryTests {

    @Test("looks a feature up by its stable id")
    func lookup() {
        let a = StubFeature(id: "a")
        let b = StubFeature(id: "b")
        let registry = FeatureRegistry([a, b])

        #expect(registry.feature("a") === a)
        #expect(registry.feature("b") === b)
        #expect(registry.feature("missing") == nil)
    }

    @Test("preserves registration order")
    func order() {
        let registry = FeatureRegistry([
            StubFeature(id: "a"), StubFeature(id: "b"), StubFeature(id: "c"),
        ])
        #expect(registry.features.map(\.manifest.id) == ["a", "b", "c"])
        #expect(registry.manifests.map(\.id) == ["a", "b", "c"])
    }

    @Test("duplicateIDs reports each repeated id once, in first-seen order")
    func duplicateDetection() {
        let withDupes = FeatureRegistry.duplicateIDs(in: [
            StubFeature(id: "a"), StubFeature(id: "b"),
            StubFeature(id: "a"), StubFeature(id: "b"), StubFeature(id: "a"),
        ])
        #expect(withDupes == ["a", "b"])

        let clean = FeatureRegistry.duplicateIDs(in: [
            StubFeature(id: "a"), StubFeature(id: "b"),
        ])
        #expect(clean.isEmpty)
    }

    @Test("the default registry registers the Map feature and nothing twice")
    func defaultRegistry() {
        let registry = FeatureRegistry.makeDefault()

        #expect(FeatureRegistry.duplicateIDs(in: registry.features).isEmpty)

        let map = registry.feature(MapFeature.id)
        #expect(map != nil)
        #expect(map?.manifest.title == "Google Maps")
        #expect(map?.manifest.supportedSizes.contains(.full) == true)
    }

    @Test("all six sidebar features are registered with stable ids and unique names")
    func sixFeatures() {
        let registry = FeatureRegistry.makeDefault()
        let ids = ["maps", "apple-maps", "music", "weather", "speedometer", "settings"]

        #expect(registry.manifests.map(\.id) == ids)
        for id in ids {
            #expect(registry.feature(id) != nil, "\(id) should be registered")
        }
        let names = registry.manifests.map(\.title)
        #expect(Set(names).count == names.count)   // no duplicate display names
    }

    @Test("Google Maps, the Speedometer, Settings, Weather and Apple Music are real features; the rest are placeholders")
    func placeholdersResolve() {
        let registry = FeatureRegistry.makeDefault()

        #expect(registry.feature("maps") as? MapFeature != nil)
        #expect(registry.feature("speedometer") as? SpeedometerFeature != nil)
        #expect(registry.feature("settings") as? SettingsFeature != nil)
        #expect(registry.feature("weather") as? WeatherFeature != nil)
        #expect(registry.feature("music") as? AppleMusicFeature != nil)

        for id in ["apple-maps"] {
            let feature = registry.feature(id)
            #expect(feature as? PlaceholderFeature != nil, "\(id) should be a PlaceholderFeature")
            #expect(feature?.manifest.supportedSizes == [.full])
        }
    }
}
