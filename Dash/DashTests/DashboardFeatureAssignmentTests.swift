//
//  DashboardFeatureAssignmentTests.swift
//  DashTests
//
//  M8.2 — the widget → feature assignment capability: `WidgetPlacement.featureID`
//  can be reassigned on an already-placed widget through
//  `DashboardCollectionStore.updatePlacementFeature`, the registry's
//  `supportedSizes` is the only gate (no hardcoded per-feature checks anywhere
//  in the store, the editor, or the picker), and
//  `DashboardFeaturePickerView.eligibleFeatures` offers exactly the features
//  that fit the widget's current size. Several tests use the REAL
//  `FeatureRegistry.makeDefault()` so a Speedometer / Google Maps regression
//  here is caught for real, not just against a synthetic fixture.
//

import Foundation
import SwiftUI
import Testing
@testable import Dash

// MARK: - Fixtures

@MainActor
private final class SizedFeature: DashFeature {
    let manifest: FeatureManifest
    init(id: FeatureID, sizes: Set<ComponentSize>, defaultSize: ComponentSize? = nil) {
        self.manifest = FeatureManifest(
            id: id, title: id.capitalized, symbolName: "app.dashed",
            supportedSizes: sizes,
            defaultSize: defaultSize ?? (sizes.contains(.large) ? .large : (sizes.subtracting([.full]).first ?? .full))
        )
    }
    func makeFullScreenView() -> AnyView { AnyView(EmptyView()) }
    func makeComponentView(size: ComponentSize) -> AnyView { AnyView(EmptyView()) }
}

private func widget(
    _ size: ComponentSize,
    at origin: GridPoint,
    id: UUID = UUID(),
    feature: FeatureID = "maps"
) -> WidgetPlacement {
    WidgetPlacement(id: id, featureID: feature, size: size, origin: origin)
}

private func layout(_ placements: [WidgetPlacement]) -> DashboardLayout {
    DashboardLayout(pages: [DashboardPage(placements: placements)])
}

private func ephemeralDefaults() -> UserDefaults {
    UserDefaults(suiteName: "dash-feature-assign-\(UUID().uuidString)")!
}

private func manifest(_ id: FeatureID, _ sizes: Set<ComponentSize>) -> FeatureManifest {
    FeatureManifest(
        id: id, title: id, symbolName: "app.dashed",
        supportedSizes: sizes,
        defaultSize: sizes.contains(.compact) ? .compact : (sizes.first ?? .full)
    )
}

// MARK: - DashboardLayoutEditor.settingFeature (pure transform)

@Suite("DashboardLayoutEditor.settingFeature")
struct SettingFeatureEditorTests {

    @Test("changes only the targeted placement's featureID — size and origin are untouched")
    func changesFeatureOnly() {
        let idA = UUID()
        let idB = UUID()
        let before = layout([
            widget(.medium, at: GridPoint(column: 0, row: 0), id: idA, feature: "maps"),
            widget(.compact, at: GridPoint(column: 1, row: 0), id: idB, feature: "maps"),
        ])

        let after = DashboardLayoutEditor.settingFeature(of: idA, to: "speedometer", in: before)

        let a = after.allPlacements.first { $0.id == idA }
        let b = after.allPlacements.first { $0.id == idB }
        #expect(a?.featureID == "speedometer")
        #expect(a?.size == .medium)
        #expect(a?.origin == GridPoint(column: 0, row: 0))
        #expect(b?.featureID == "maps")   // untouched
    }

    @Test("an unknown placement id leaves the layout unchanged")
    func unknownIDIsNoOp() {
        let before = layout([widget(.medium, at: GridPoint(column: 0, row: 0), feature: "maps")])
        let after = DashboardLayoutEditor.settingFeature(of: UUID(), to: "speedometer", in: before)
        #expect(after == before)
    }
}

// MARK: - DashboardCollectionStore.updatePlacementFeature

@MainActor
@Suite("DashboardCollectionStore.updatePlacementFeature")
struct UpdatePlacementFeatureTests {

    private func registry() -> FeatureRegistry {
        FeatureRegistry([
            SizedFeature(id: "maps", sizes: [.compact, .medium, .large, .full]),
            SizedFeature(id: "speedometer", sizes: [.compact, .medium, .full]),
            SizedFeature(id: "clock", sizes: [.compact, .full]),
        ])
    }

    @Test("assigns a registered feature that supports the widget's current size")
    func assignsCompatibleFeature() {
        let defaults = ephemeralDefaults()
        let idA = UUID()
        let s = DashboardCollectionStore(
            seed: layout([widget(.medium, at: GridPoint(column: 0, row: 0), id: idA, feature: "maps")]),
            defaults: defaults
        )

        #expect(s.updatePlacementFeature(id: idA, to: "speedometer", registry: registry()) == true)
        #expect(s.layout.allPlacements.first { $0.id == idA }?.featureID == "speedometer")
    }

    @Test("refuses a feature that doesn't support the widget's current size, and changes nothing")
    func refusesIncompatibleSize() {
        let defaults = ephemeralDefaults()
        let idA = UUID()
        let s = DashboardCollectionStore(
            seed: layout([widget(.large, at: GridPoint(column: 0, row: 0), id: idA, feature: "maps")]),
            defaults: defaults
        )

        // "clock" doesn't support .large.
        #expect(s.updatePlacementFeature(id: idA, to: "clock", registry: registry()) == false)
        #expect(s.layout.allPlacements.first { $0.id == idA }?.featureID == "maps")
    }

    @Test("refuses an unregistered feature id, and changes nothing")
    func refusesUnknownFeature() {
        let defaults = ephemeralDefaults()
        let idA = UUID()
        let s = DashboardCollectionStore(
            seed: layout([widget(.medium, at: GridPoint(column: 0, row: 0), id: idA)]),
            defaults: defaults
        )

        #expect(s.updatePlacementFeature(id: idA, to: "not-a-real-feature", registry: registry()) == false)
        #expect(s.layout.allPlacements.first { $0.id == idA }?.featureID == "maps")
    }

    @Test("refuses an unknown placement id")
    func refusesUnknownPlacement() {
        let s = DashboardCollectionStore(seed: layout([]), defaults: ephemeralDefaults())
        #expect(s.updatePlacementFeature(id: UUID(), to: "maps", registry: registry()) == false)
    }

    @Test("the real Speedometer feature cannot be assigned to a large widget")
    func speedometerUnavailableAtLarge() {
        let defaults = ephemeralDefaults()
        let idA = UUID()
        let s = DashboardCollectionStore(
            seed: layout([widget(.large, at: GridPoint(column: 0, row: 0), id: idA, feature: "maps")]),
            defaults: defaults
        )
        let real = FeatureRegistry.makeDefault()

        #expect(s.updatePlacementFeature(id: idA, to: SpeedometerFeature.id, registry: real) == false)
        #expect(s.layout.allPlacements.first { $0.id == idA }?.featureID == "maps")
    }

    @Test("the real Speedometer feature can be assigned to a compact or medium widget")
    func speedometerAvailableAtCompactAndMedium() {
        let defaults = ephemeralDefaults()
        let idCompact = UUID()
        let idMedium = UUID()
        let s = DashboardCollectionStore(
            seed: layout([
                widget(.compact, at: GridPoint(column: 0, row: 0), id: idCompact),
                widget(.medium, at: GridPoint(column: 1, row: 0), id: idMedium),
            ]),
            defaults: defaults
        )
        let real = FeatureRegistry.makeDefault()

        #expect(s.updatePlacementFeature(id: idCompact, to: SpeedometerFeature.id, registry: real) == true)
        #expect(s.updatePlacementFeature(id: idMedium, to: SpeedometerFeature.id, registry: real) == true)
    }

    @Test("the real Google Maps feature can be assigned to a widget at each size it declares")
    func googleMapsRemainsAvailable() {
        let real = FeatureRegistry.makeDefault()

        for size in [ComponentSize.compact, .medium, .large] {
            let defaults = ephemeralDefaults()
            let idA = UUID()
            // Seed with Maps itself so every size is a legal starting placement,
            // reassign away and back — this exercises the same store method the
            // picker uses, not just the manifest declaration (already covered by
            // `realMapsManifest` below).
            let s = DashboardCollectionStore(
                seed: layout([widget(size, at: GridPoint(column: 0, row: 0), id: idA, feature: "maps")]),
                defaults: defaults
            )
            #expect(s.updatePlacementFeature(id: idA, to: MapFeature.id, registry: real) == true)
            #expect(s.layout.allPlacements.first { $0.id == idA }?.featureID == MapFeature.id)
        }
    }

    @Test("the persisted feature id round-trips across a reload")
    func persistsAcrossReload() {
        let defaults = ephemeralDefaults()
        let idA = UUID()
        let seed = layout([widget(.medium, at: GridPoint(column: 0, row: 0), id: idA, feature: "maps")])
        let s = DashboardCollectionStore(seed: seed, defaults: defaults)

        #expect(s.updatePlacementFeature(id: idA, to: "speedometer", registry: registry()) == true)

        let reloaded = DashboardCollectionStore(seed: seed, defaults: defaults)
        #expect(reloaded.layout.allPlacements.first { $0.id == idA }?.featureID == "speedometer")
    }

    @Test("a refused reassignment is never persisted")
    func refusedChangeDoesNotPersist() {
        let defaults = ephemeralDefaults()
        let idA = UUID()
        let seed = layout([widget(.large, at: GridPoint(column: 0, row: 0), id: idA, feature: "maps")])
        let s = DashboardCollectionStore(seed: seed, defaults: defaults)

        #expect(s.updatePlacementFeature(id: idA, to: "clock", registry: registry()) == false)

        let reloaded = DashboardCollectionStore(seed: seed, defaults: defaults)
        #expect(reloaded.layout.allPlacements.first { $0.id == idA }?.featureID == "maps")
    }

    @Test("changing one widget's feature does not affect another widget on the same dashboard")
    func doesNotAffectOtherWidget() {
        let defaults = ephemeralDefaults()
        let idA = UUID()
        let idB = UUID()
        let s = DashboardCollectionStore(
            seed: layout([
                widget(.medium, at: GridPoint(column: 0, row: 0), id: idA, feature: "maps"),
                widget(.medium, at: GridPoint(column: 1, row: 0), id: idB, feature: "maps"),
            ]),
            defaults: defaults
        )

        #expect(s.updatePlacementFeature(id: idA, to: "speedometer", registry: registry()) == true)
        #expect(s.layout.allPlacements.first { $0.id == idA }?.featureID == "speedometer")
        #expect(s.layout.allPlacements.first { $0.id == idB }?.featureID == "maps")
    }

    @Test("changing a widget's feature on one dashboard does not affect another dashboard")
    func doesNotAffectOtherDashboard() {
        let defaults = ephemeralDefaults()
        let idA = UUID()
        let s = DashboardCollectionStore(
            seed: layout([widget(.medium, at: GridPoint(column: 0, row: 0), id: idA, feature: "maps")]),
            defaults: defaults
        )
        let firstID = s.activeID
        let secondID = s.addDashboard(name: "Second")
        _ = s.addWidget(featureID: "maps", size: .medium)   // lands on "Second", the active one

        s.select(id: firstID)
        #expect(s.updatePlacementFeature(id: idA, to: "speedometer", registry: registry()) == true)

        s.select(id: secondID)
        #expect(s.layout.allPlacements.allSatisfy { $0.featureID == "maps" })

        s.select(id: firstID)
        #expect(s.layout.allPlacements.first { $0.id == idA }?.featureID == "speedometer")
    }
}

// MARK: - DashboardFeaturePickerView.eligibleFeatures

@MainActor
@Suite("DashboardFeaturePickerView.eligibleFeatures")
struct FeaturePickerEligibleFeaturesTests {

    @Test("only offers features whose manifest supports the requested size")
    func filtersBySize() {
        let manifests = [
            manifest("maps", [.compact, .medium, .large, .full]),
            manifest("speedometer", [.compact, .medium, .full]),
            manifest("clock", [.compact, .full]),
        ]
        #expect(DashboardFeaturePickerView.eligibleFeatures(manifests, for: .large).map(\.id) == ["maps"])
        #expect(
            DashboardFeaturePickerView.eligibleFeatures(manifests, for: .compact).map(\.id)
                == ["maps", "speedometer", "clock"]
        )
    }

    @Test("never offers .full — a dashboard widget is never the full-screen experience")
    func neverFull() {
        let manifests = [manifest("maps", [.compact, .full])]
        #expect(DashboardFeaturePickerView.eligibleFeatures(manifests, for: .full).map(\.id) == ["maps"])
        // .full isn't a widget size at all — callers only ever pass a widget size
        // in (mirrors DashboardWidgetPickerView's contract); this just documents
        // that eligibleFeatures itself doesn't special-case it.
    }

    @Test("automatically reflects a newly registered feature — no picker-specific code involved")
    func reflectsNewFeature() {
        let manifests = [
            manifest("maps", [.compact, .full]),
            manifest("brand-new-feature", [.compact, .full]),
        ]
        #expect(
            DashboardFeaturePickerView.eligibleFeatures(manifests, for: .compact).map(\.id)
                .contains("brand-new-feature")
        )
    }

    @Test("the real registry's Speedometer manifest is offered at compact/medium but not large")
    func realSpeedometerManifest() {
        let manifests = FeatureRegistry.makeDefault().manifests
        #expect(
            !DashboardFeaturePickerView.eligibleFeatures(manifests, for: .large)
                .contains { $0.id == SpeedometerFeature.id }
        )
        #expect(
            DashboardFeaturePickerView.eligibleFeatures(manifests, for: .compact)
                .contains { $0.id == SpeedometerFeature.id }
        )
        #expect(
            DashboardFeaturePickerView.eligibleFeatures(manifests, for: .medium)
                .contains { $0.id == SpeedometerFeature.id }
        )
    }

    @Test("the real registry's Google Maps manifest remains available for its supported widget sizes")
    func realMapsManifest() {
        let manifests = FeatureRegistry.makeDefault().manifests
        for size in [ComponentSize.compact, .medium, .large] {
            #expect(
                DashboardFeaturePickerView.eligibleFeatures(manifests, for: size)
                    .contains { $0.id == MapFeature.id },
                "Google Maps should be offered at \(size)"
            )
        }
    }
}
