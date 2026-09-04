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
}
