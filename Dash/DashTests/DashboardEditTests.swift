//
//  DashboardEditTests.swift
//  DashTests
//
//  M5.4.1 — the Dashboard customization foundation:
//    • `DashboardEditModel` — the transient edit-mode flag.
//    • `WidgetHostView` disables tap-to-open while editing.
//    • `DashboardLayoutEditor` — pure layout transforms.
//    • `DashboardCollectionStore`'s validated mutation API (remove / resize / add /
//      move) — validates with `DashboardLayoutValidator` before persisting, and
//      rejects (leaving the store untouched) anything structurally invalid.
//
//  No drag / resize gestures / visual polish here — that is M5.4.2.
//

import Foundation
import SwiftUI
import Testing
@testable import Dash

// MARK: - Fixtures

private func widget(
    _ id: UUID,
    _ size: ComponentSize = .compact,
    at origin: GridPoint = GridPoint(column: 0, row: 0),
    feature: FeatureID = "maps"
) -> WidgetPlacement {
    WidgetPlacement(id: id, featureID: feature, size: size, origin: origin)
}

/// A stable signature so tests can compare layouts without depending on freshly
/// minted `DashboardPage` ids.
private func signature(_ layout: DashboardLayout) -> [String] {
    layout.allPlacements.map {
        "\($0.id)|\($0.featureID)|\($0.size.rawValue)|\($0.origin.column),\($0.origin.row)"
    }
}

private func ephemeralDefaults() -> UserDefaults {
    UserDefaults(suiteName: "dash-edit-\(UUID().uuidString)")!
}

// MARK: - Edit-mode flag

@MainActor
@Suite("DashboardEditModel")
struct DashboardEditModelTests {

    @Test("starts in normal mode")
    func startsNormal() {
        #expect(DashboardEditModel().isEditing == false)
    }

    @Test("begin / end / toggle move between the two modes; both are idempotent")
    func transitions() {
        let model = DashboardEditModel()

        model.beginEditing()
        #expect(model.isEditing)
        model.beginEditing()
        #expect(model.isEditing)

        model.endEditing()
        #expect(model.isEditing == false)
        model.endEditing()
        #expect(model.isEditing == false)

        model.toggle()
        #expect(model.isEditing)
        model.toggle()
        #expect(model.isEditing == false)
    }
}

// MARK: - Widget interaction is disabled while editing

@MainActor
@Suite("WidgetHostView while editing")
struct WidgetHostEditingTests {

    @Test("tapping a widget opens its feature when not editing")
    func opensWhenNotEditing() {
        var requested: [FeatureID] = []
        WidgetHostView(
            placement: widget(UUID(), .large),
            registry: FeatureRegistry([]),
            onOpenFeature: { requested.append($0) },
            isEditing: false
        ).activate()

        #expect(requested == ["maps"])
    }

    @Test("tapping a widget does nothing while the dashboard is being edited")
    func inertWhileEditing() {
        var requested: [FeatureID] = []
        WidgetHostView(
            placement: widget(UUID(), .large),
            registry: FeatureRegistry([]),
            onOpenFeature: { requested.append($0) },
            isEditing: true
        ).activate()

        #expect(requested.isEmpty)
    }

    @Test("the default (no isEditing argument) keeps the M5.3.0 open behaviour")
    func defaultIsNotEditing() {
        var requested: [FeatureID] = []
        WidgetHostView(
            placement: widget(UUID()),
            registry: FeatureRegistry([]),
            onOpenFeature: { requested.append($0) }
        ).activate()

        #expect(requested == ["maps"])
    }
}

// MARK: - Pure layout transforms

@Suite("DashboardLayoutEditor")
struct DashboardLayoutEditorTests {

    private let a = UUID()
    private let b = UUID()

    private func base() -> DashboardLayout {
        DashboardLayout(pages: [DashboardPage(placements: [
            widget(a, .compact, at: GridPoint(column: 0, row: 0)),
            widget(b, .compact, at: GridPoint(column: 2, row: 0)),
        ])])
    }

    @Test("removing drops exactly the matching placement, keeps the rest")
    func removing() {
        let out = DashboardLayoutEditor.removing(placementID: a, from: base())
        #expect(out.allPlacements.map(\.id) == [b])
    }

    @Test("removing an unknown id leaves the layout unchanged")
    func removingUnknown() {
        let input = base()
        let out = DashboardLayoutEditor.removing(placementID: UUID(), from: input)
        #expect(signature(out) == signature(input))
    }

    @Test("settingSize changes only that placement's size, preserving id + origin")
    func settingSize() {
        let out = DashboardLayoutEditor.settingSize(of: a, to: .large, in: base())
        let changed = out.allPlacements.first { $0.id == a }
        #expect(changed?.size == .large)
        #expect(changed?.origin == GridPoint(column: 0, row: 0))
        #expect(out.allPlacements.first { $0.id == b }?.size == .compact)
    }

    @Test("moving changes only that placement's origin")
    func moving() {
        let out = DashboardLayoutEditor.moving(placementID: b, to: GridPoint(column: 4, row: 3), in: base())
        #expect(out.allPlacements.first { $0.id == b }?.origin == GridPoint(column: 4, row: 3))
        #expect(out.allPlacements.first { $0.id == a }?.origin == GridPoint(column: 0, row: 0))
    }

    @Test("adding appends to the given page; out-of-range page is a no-op")
    func adding() {
        let added = widget(UUID(), .compact, at: GridPoint(column: 4, row: 0))
        let out = DashboardLayoutEditor.adding(added, toPageAt: 0, in: base())
        #expect(out.allPlacements.map(\.id) == [a, b, added.id])

        let unchanged = DashboardLayoutEditor.adding(added, toPageAt: 5, in: base())
        #expect(signature(unchanged) == signature(base()))
    }

    @Test("page identity is preserved across every transform")
    func pageIdentityStable() {
        let input = base()
        let pageID = input.pages[0].id
        let added = widget(UUID(), .compact, at: GridPoint(column: 4, row: 0))

        #expect(DashboardLayoutEditor.removing(placementID: a, from: input).pages[0].id == pageID)
        #expect(DashboardLayoutEditor.settingSize(of: a, to: .medium, in: input).pages[0].id == pageID)
        #expect(DashboardLayoutEditor.moving(placementID: a, to: GridPoint(column: 0, row: 2), in: input).pages[0].id == pageID)
        #expect(DashboardLayoutEditor.adding(added, toPageAt: 0, in: input).pages[0].id == pageID)
    }
}

// MARK: - Validated mutation API on the store

@MainActor
@Suite("DashboardCollectionStore customization")
struct DashboardCollectionStoreCustomizationTests {

    private let idA = UUID()
    private let idB = UUID()
    private let pageID = UUID()

    /// Two compacts stacked in column 0 (rows 0..2 and 2..4) — structurally valid.
    private func baseLayout() -> DashboardLayout {
        DashboardLayout(pages: [DashboardPage(id: pageID, placements: [
            widget(idA, .compact, at: GridPoint(column: 0, row: 0)),
            widget(idB, .compact, at: GridPoint(column: 0, row: 2)),
        ])])
    }

    private func store(_ defaults: UserDefaults) -> DashboardCollectionStore {
        DashboardCollectionStore(seed: baseLayout(), defaults: defaults)
    }

    // MARK: remove

    @Test("removePlacement drops the widget and persists")
    func removePersists() {
        let defaults = ephemeralDefaults()
        let s = store(defaults)

        #expect(s.removePlacement(id: idA) == true)
        #expect(s.layout.allPlacements.map(\.id) == [idB])

        let reloaded = DashboardCollectionStore(seed: baseLayout(), defaults: defaults)
        #expect(signature(reloaded.layout) == signature(s.layout))
    }

    @Test("removePlacement with an unknown id is a no-op and returns false")
    func removeUnknown() {
        let s = store(ephemeralDefaults())
        let before = signature(s.layout)

        #expect(s.removePlacement(id: UUID()) == false)
        #expect(signature(s.layout) == before)
    }

    // MARK: resize

    @Test("updatePlacementSize applies a valid resize and persists")
    func resizeValid() {
        let defaults = ephemeralDefaults()
        // Solo compact so growing it stays in bounds and collides with nothing.
        let solo = DashboardLayout(pages: [DashboardPage(id: pageID, placements: [
            widget(idA, .compact, at: GridPoint(column: 0, row: 0)),
        ])])
        let s = DashboardCollectionStore(seed: solo, defaults: defaults)

        #expect(s.updatePlacementSize(id: idA, to: .large) == true)
        #expect(s.layout.allPlacements.first?.size == .large)

        let reloaded = DashboardCollectionStore(seed: solo, defaults: defaults)
        #expect(reloaded.layout.allPlacements.first?.size == .large)
    }

    @Test("updatePlacementSize is rejected when the result would overlap, and nothing persists")
    func resizeRejectedOnOverlap() {
        let defaults = ephemeralDefaults()
        let s = store(defaults)          // idA compact @ (0,0), idB compact @ (0,2)
        let before = signature(s.layout)

        // idA → medium (rows 0..3) would collide with idB (rows 2..4).
        #expect(s.updatePlacementSize(id: idA, to: .medium) == false)
        #expect(signature(s.layout) == before)

        let reloaded = DashboardCollectionStore(seed: baseLayout(), defaults: defaults)
        #expect(signature(reloaded.layout) == before)
    }

    @Test("updatePlacementSize is rejected when the result would leave the grid")
    func resizeRejectedOutOfBounds() {
        let defaults = ephemeralDefaults()
        // Compact near the bottom; growing to medium (3 rows tall) runs off row 6.
        let low = DashboardLayout(pages: [DashboardPage(id: pageID, placements: [
            widget(idA, .compact, at: GridPoint(column: 0, row: 4)),
        ])])
        let s = DashboardCollectionStore(seed: low, defaults: defaults)

        #expect(s.updatePlacementSize(id: idA, to: .medium) == false)
        #expect(s.layout.allPlacements.first?.size == .compact)
    }

    // MARK: add

    @Test("addPlacement inserts a valid widget and persists")
    func addValid() {
        let defaults = ephemeralDefaults()
        let s = store(defaults)
        let added = widget(UUID(), .compact, at: GridPoint(column: 1, row: 0))

        #expect(s.addPlacement(added) == true)
        #expect(s.layout.allPlacements.map(\.id) == [idA, idB, added.id])

        let reloaded = DashboardCollectionStore(seed: baseLayout(), defaults: defaults)
        #expect(reloaded.layout.allPlacements.map(\.id) == [idA, idB, added.id])
    }

    @Test("addPlacement is rejected when the new widget overlaps an existing one")
    func addRejectedOnOverlap() {
        let s = store(ephemeralDefaults())
        let before = signature(s.layout)

        #expect(s.addPlacement(widget(UUID(), .compact, at: GridPoint(column: 0, row: 1))) == false)
        #expect(signature(s.layout) == before)
    }

    @Test("addPlacement is rejected when the new widget is out of bounds")
    func addRejectedOutOfBounds() {
        let s = store(ephemeralDefaults())
        let before = signature(s.layout)

        #expect(s.addPlacement(widget(UUID(), .compact, at: GridPoint(column: 2, row: 0))) == false)
        #expect(signature(s.layout) == before)
    }

    @Test("addPlacement to a page that doesn't exist returns false")
    func addRejectedBadPage() {
        let s = store(ephemeralDefaults())
        #expect(s.addPlacement(widget(UUID(), .compact, at: GridPoint(column: 4, row: 2)), toPageAt: 7) == false)
    }

    @Test("a full-size placement is rejected — it is not a widget size")
    func addRejectedNotAWidget() {
        let s = store(ephemeralDefaults())
        #expect(s.addPlacement(widget(UUID(), .full, at: GridPoint(column: 0, row: 2))) == false)
    }

    // MARK: move

    @Test("movePlacement applies a valid move and persists")
    func moveValid() {
        let defaults = ephemeralDefaults()
        let s = store(defaults)

        #expect(s.movePlacement(id: idB, to: GridPoint(column: 1, row: 0)) == true)
        #expect(s.layout.allPlacements.first { $0.id == idB }?.origin == GridPoint(column: 1, row: 0))

        let reloaded = DashboardCollectionStore(seed: baseLayout(), defaults: defaults)
        #expect(reloaded.layout.allPlacements.first { $0.id == idB }?.origin == GridPoint(column: 1, row: 0))
    }

    @Test("movePlacement is rejected when the target would overlap or leave the grid")
    func moveRejected() {
        let s = store(ephemeralDefaults())
        let before = signature(s.layout)

        #expect(s.movePlacement(id: idB, to: GridPoint(column: 0, row: 0)) == false) // onto idA
        #expect(s.movePlacement(id: idB, to: GridPoint(column: 2, row: 0)) == false) // column 2 off grid
        #expect(signature(s.layout) == before)
    }

    @Test("movePlacement with an unknown id returns false")
    func moveUnknown() {
        let s = store(ephemeralDefaults())
        #expect(s.movePlacement(id: UUID(), to: GridPoint(column: 4, row: 2)) == false)
    }

    // MARK: persistence contract shared with load-time validation

    @Test("a rejected mutation never reaches disk — the reloaded store is the last valid layout")
    func rejectedMutationsDoNotPersist() {
        let defaults = ephemeralDefaults()
        let s = store(defaults)

        // One good change…
        #expect(s.removePlacement(id: idA) == true)
        let afterValid = signature(s.layout)

        // …then several rejected ones.
        #expect(s.addPlacement(widget(UUID(), .compact, at: GridPoint(column: 0, row: 2))) == false)
        #expect(s.updatePlacementSize(id: idB, to: .full) == false)
        #expect(s.movePlacement(id: idB, to: GridPoint(column: 2, row: 0)) == false)

        #expect(signature(s.layout) == afterValid)
        let reloaded = DashboardCollectionStore(seed: baseLayout(), defaults: defaults)
        #expect(signature(reloaded.layout) == afterValid)
    }
}
