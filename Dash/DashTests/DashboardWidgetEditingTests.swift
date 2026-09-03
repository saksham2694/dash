//
//  DashboardWidgetEditingTests.swift
//  DashTests
//
//  M5.4.2 — the Dashboard widget-editing UI's testable core:
//    • `DashboardLayoutEditor.firstFreeOrigin` — deterministic top-left first-fit.
//    • `DashboardLayoutStore.addWidget` — auto-place + "no room" outcome.
//    • `DashboardWidgetPickerView.offeredSizes` — only feature-supported sizes.
//    • `WidgetHostView` size control / open behaviour.
//    • add / remove / resize all persist through `DashboardLayoutStore`.
//

import Foundation
import SwiftUI
import Testing
@testable import Dash

// MARK: - Fixtures

@MainActor
private final class SizedFeature: DashFeature {
    let manifest: FeatureManifest
    init(id: FeatureID, sizes: Set<ComponentSize>) {
        self.manifest = FeatureManifest(
            id: id, title: id.capitalized, symbolName: "app.dashed",
            supportedSizes: sizes,
            defaultSize: sizes.contains(.large) ? .large : (sizes.subtracting([.full]).first ?? .full)
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
    UserDefaults(suiteName: "dash-edit2-\(UUID().uuidString)")!
}

private func manifest(_ sizes: Set<ComponentSize>) -> FeatureManifest {
    FeatureManifest(
        id: "f", title: "F", symbolName: "app",
        supportedSizes: sizes,
        defaultSize: sizes.contains(.compact) ? .compact : (sizes.first ?? .full)
    )
}

// MARK: - First-fit placement

@Suite("DashboardLayoutEditor.firstFreeOrigin")
struct FirstFreeOriginTests {

    let grid = DashboardGrid.standard   // 6 × 4

    @Test("an empty page places a widget at the very top-left")
    func emptyPage() {
        let origin = DashboardLayoutEditor.firstFreeOrigin(
            for: .compact, onPageAt: 0, in: layout([]), grid: grid
        )
        #expect(origin == GridPoint(column: 0, row: 0))
    }

    @Test("a large widget across the top pushes the next one to the first free row")
    func belowALarge() {
        let l = layout([widget(.large, at: GridPoint(column: 0, row: 0))]) // rows 0..2
        #expect(
            DashboardLayoutEditor.firstFreeOrigin(for: .compact, onPageAt: 0, in: l, grid: grid)
                == GridPoint(column: 0, row: 2)
        )
    }

    @Test("scans left-to-right within a row, then down — matching the starter layout's gap")
    func deterministicScan() {
        // large across rows 0..2, medium in the bottom-left (cols 0..3, rows 2..4).
        let l = layout([
            widget(.large, at: GridPoint(column: 0, row: 0)),
            widget(.medium, at: GridPoint(column: 0, row: 2)),
        ])
        #expect(
            DashboardLayoutEditor.firstFreeOrigin(for: .compact, onPageAt: 0, in: l, grid: grid)
                == GridPoint(column: 3, row: 2)
        )
    }

    @Test("the returned origin never overlaps an existing widget and stays in bounds")
    func neverOverlaps() {
        let existing = [
            widget(.large, at: GridPoint(column: 0, row: 0)),
            widget(.compact, at: GridPoint(column: 0, row: 2)),
            widget(.compact, at: GridPoint(column: 2, row: 3)),
        ]
        let l = layout(existing)

        for size in ComponentSize.widgetSizes {
            guard let origin = DashboardLayoutEditor.firstFreeOrigin(
                for: size, onPageAt: 0, in: l, grid: grid
            ) else { continue }

            let candidate = GridRect(origin: origin, span: grid.span(for: size))
            #expect(grid.contains(candidate))
            for placement in existing {
                #expect(!grid.rect(for: placement).intersects(candidate))
            }
        }
    }

    @Test("a full dashboard has no free slot")
    func fullDashboard() {
        // Two larges (6×2 each) tile the whole 6×4 grid.
        let full = layout([
            widget(.large, at: GridPoint(column: 0, row: 0)),
            widget(.large, at: GridPoint(column: 0, row: 2)),
        ])
        for size in ComponentSize.widgetSizes {
            #expect(DashboardLayoutEditor.firstFreeOrigin(for: size, onPageAt: 0, in: full, grid: grid) == nil)
        }
    }

    @Test("a non-widget size and a missing page yield nil")
    func rejectsBadInput() {
        #expect(DashboardLayoutEditor.firstFreeOrigin(for: .full, onPageAt: 0, in: layout([]), grid: grid) == nil)
        #expect(DashboardLayoutEditor.firstFreeOrigin(for: .compact, onPageAt: 3, in: layout([]), grid: grid) == nil)
    }
}

// MARK: - Store: add widget with auto-placement

@MainActor
@Suite("DashboardLayoutStore.addWidget")
struct AddWidgetTests {

    private func store(_ seed: DashboardLayout, _ defaults: UserDefaults) -> DashboardLayoutStore {
        DashboardLayoutStore(seed: seed, defaults: defaults)
    }

    @Test("adds a widget at the first free slot and persists it")
    func addsAndPersists() {
        let defaults = ephemeralDefaults()
        let seed = layout([widget(.large, at: GridPoint(column: 0, row: 0))])
        let s = store(seed, defaults)

        let outcome = s.addWidget(featureID: "maps", size: .compact)

        guard case .added(let newID) = outcome else {
            Issue.record("expected .added, got \(outcome)")
            return
        }
        let added = s.layout.allPlacements.first { $0.id == newID }
        #expect(added?.size == .compact)
        #expect(added?.origin == GridPoint(column: 0, row: 2)) // first free row under the large

        let reloaded = DashboardLayoutStore(seed: seed, defaults: defaults)
        #expect(reloaded.layout.allPlacements.contains { $0.id == newID })
    }

    @Test("reports .noSpace on a full dashboard and changes nothing")
    func noSpace() {
        let defaults = ephemeralDefaults()
        let full = layout([
            widget(.large, at: GridPoint(column: 0, row: 0)),
            widget(.large, at: GridPoint(column: 0, row: 2)),
        ])
        let s = store(full, defaults)
        let before = s.layout.allPlacements.count

        #expect(s.addWidget(featureID: "maps", size: .compact) == .noSpace)
        #expect(s.layout.allPlacements.count == before)
    }

    @Test("rejects a non-widget size outright")
    func rejectsFull() {
        let s = store(layout([]), ephemeralDefaults())
        #expect(s.addWidget(featureID: "maps", size: .full) == .rejected)
        #expect(s.layout.allPlacements.isEmpty)
    }

    @Test("the feature id is opaque — any id is accepted and placed")
    func featureAgnostic() {
        let s = store(layout([]), ephemeralDefaults())
        let outcome = s.addWidget(featureID: "speedometer", size: .medium)
        if case .added = outcome {} else { Issue.record("expected .added, got \(outcome)") }
        #expect(s.layout.allPlacements.first?.featureID == "speedometer")
    }
}

// MARK: - Picker: only feature-supported sizes

@Suite("DashboardWidgetPickerView.offeredSizes")
struct PickerOfferedSizesTests {

    @Test("offers every supported widget size, in compact→large order")
    func allWidgetSizes() {
        #expect(
            DashboardWidgetPickerView.offeredSizes(for: manifest([.compact, .medium, .large, .full]))
                == [.compact, .medium, .large]
        )
    }

    @Test("never offers .full — it is the full-screen experience, not a widget")
    func neverFull() {
        #expect(!DashboardWidgetPickerView.offeredSizes(for: manifest([.compact, .full])).contains(.full))
    }

    @Test("a feature that supports only some sizes is offered only those")
    func partialSupport() {
        #expect(DashboardWidgetPickerView.offeredSizes(for: manifest([.large, .full])) == [.large])
        #expect(DashboardWidgetPickerView.offeredSizes(for: manifest([.compact, .large, .full])) == [.compact, .large])
    }

    @Test("a feature with no widget sizes offers nothing")
    func widgetlessFeature() {
        #expect(DashboardWidgetPickerView.offeredSizes(for: manifest([.full])).isEmpty)
    }
}

// MARK: - WidgetHostView open / edit behaviour + size control

@MainActor
@Suite("WidgetHostView editing controls")
struct WidgetHostEditingControlsTests {

    private func registry() -> FeatureRegistry {
        FeatureRegistry([
            SizedFeature(id: "maps", sizes: [.compact, .medium, .large, .full]),
            SizedFeature(id: "clock", sizes: [.compact, .full]),
        ])
    }

    @Test("normal mode: tapping the widget opens its feature")
    func normalOpens() {
        var opened: [FeatureID] = []
        WidgetHostView(
            placement: widget(.large, at: .init(column: 0, row: 0), feature: "maps"),
            registry: registry(),
            onOpenFeature: { opened.append($0) },
            isEditing: false
        ).activate()
        #expect(opened == ["maps"])
    }

    @Test("edit mode: tapping the widget does nothing")
    func editingInert() {
        var opened: [FeatureID] = []
        WidgetHostView(
            placement: widget(.large, at: .init(column: 0, row: 0), feature: "maps"),
            registry: registry(),
            onOpenFeature: { opened.append($0) },
            isEditing: true
        ).activate()
        #expect(opened.isEmpty)
    }

    @Test("the size control lists only the feature's supported widget sizes, in order")
    func sizeControlSupportedOnly() {
        let maps = WidgetHostView(
            placement: widget(.medium, at: .init(column: 0, row: 0), feature: "maps"),
            registry: registry(), onOpenFeature: { _ in }, isEditing: true
        )
        #expect(maps.supportedWidgetSizes == [.compact, .medium, .large])

        // A feature with a single widget size → the control hides itself (count <= 1).
        let clock = WidgetHostView(
            placement: widget(.compact, at: .init(column: 0, row: 0), feature: "clock"),
            registry: registry(), onOpenFeature: { _ in }, isEditing: true
        )
        #expect(clock.supportedWidgetSizes == [.compact])
    }
}

// MARK: - add / remove / resize persist through the store

@MainActor
@Suite("Dashboard editing round-trips through DashboardLayoutStore")
struct DashboardEditingPersistenceTests {

    private let idA = UUID()
    private let pageID = UUID()

    private func seed() -> DashboardLayout {
        DashboardLayout(pages: [DashboardPage(id: pageID, placements: [
            widget(.compact, at: GridPoint(column: 0, row: 0), id: idA),
        ])])
    }

    @Test("adding a widget persists across a reload")
    func addPersists() {
        let defaults = ephemeralDefaults()
        let s = DashboardLayoutStore(seed: seed(), defaults: defaults)

        _ = s.addWidget(featureID: "maps", size: .compact)
        let reloaded = DashboardLayoutStore(seed: seed(), defaults: defaults)
        #expect(reloaded.layout.allPlacements.count == 2)
    }

    @Test("removing a widget persists across a reload")
    func removePersists() {
        let defaults = ephemeralDefaults()
        let s = DashboardLayoutStore(seed: seed(), defaults: defaults)

        #expect(s.removePlacement(id: idA) == true)
        let reloaded = DashboardLayoutStore(seed: seed(), defaults: defaults)
        #expect(reloaded.layout.allPlacements.isEmpty)
    }

    @Test("changing a widget's size persists across a reload")
    func resizePersists() {
        let defaults = ephemeralDefaults()
        let s = DashboardLayoutStore(seed: seed(), defaults: defaults)

        #expect(s.updatePlacementSize(id: idA, to: .large) == true)
        let reloaded = DashboardLayoutStore(seed: seed(), defaults: defaults)
        #expect(reloaded.layout.allPlacements.first?.size == .large)
    }

    @Test("an invalid size change leaves the stored layout untouched")
    func invalidResizeIsInert() {
        let defaults = ephemeralDefaults()
        // Two compacts that would collide if the first grows to medium.
        let two = DashboardLayout(pages: [DashboardPage(id: pageID, placements: [
            widget(.compact, at: GridPoint(column: 0, row: 0), id: idA),
            widget(.compact, at: GridPoint(column: 2, row: 0)),
        ])])
        let s = DashboardLayoutStore(seed: two, defaults: defaults)

        #expect(s.updatePlacementSize(id: idA, to: .medium) == false)
        #expect(s.layout.allPlacements.first { $0.id == idA }?.size == .compact)

        let reloaded = DashboardLayoutStore(seed: two, defaults: defaults)
        #expect(reloaded.layout.allPlacements.first { $0.id == idA }?.size == .compact)
    }
}
