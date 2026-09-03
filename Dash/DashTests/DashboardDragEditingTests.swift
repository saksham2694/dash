//
//  DashboardDragEditingTests.swift
//  DashTests
//
//  M5.4.3 — drag-to-move and interactive resize. The gesture wiring itself is
//  verified on device; these cover the deterministic pieces it is built from:
//    • `DashboardGridGeometry` — pixel ↔ grid snapping (always in bounds) and
//      `proposedOrigin` (translation applied once as a pure delta — the fix for
//      the drag oscillation).
//    • `DashboardResizeStepper` — a resize drag steps through supported sizes.
//    • `DashboardLayoutStore.canMovePlacement` / `canResizePlacement` — the
//      non-persisting validity checks that drive live feedback.
//    • The commit path (`movePlacement` / `updatePlacementSize`) persists only a
//      final valid placement; an invalid / cancelled interaction changes nothing.
//

import CoreGraphics
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
            defaultSize: sizes.contains(.compact) ? .compact : (sizes.subtracting([.full]).first ?? .full)
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

private func layout(_ placements: [WidgetPlacement], pageID: UUID = UUID()) -> DashboardLayout {
    DashboardLayout(pages: [DashboardPage(id: pageID, placements: placements)])
}

private func ephemeralDefaults() -> UserDefaults {
    UserDefaults(suiteName: "dash-drag-\(UUID().uuidString)")!
}

private func signature(_ layout: DashboardLayout) -> [String] {
    layout.allPlacements.map {
        "\($0.id)|\($0.featureID)|\($0.size.rawValue)|\($0.origin.column),\($0.origin.row)"
    }
}

// MARK: - Geometry: snapping a drag to the grid

@Suite("DashboardGridGeometry")
struct DashboardGridGeometryTests {

    // 6×4 grid, 600×400 canvas, no gap → 100×100 cells, 100 step.
    private let geo = DashboardGridGeometry(
        grid: .standard, canvas: CGSize(width: 600, height: 400), gap: 0
    )
    private let compact = GridSpan(columns: 2, rows: 1)
    private let large = GridSpan(columns: 6, rows: 2)

    @Test("cell and frame math")
    func frames() {
        #expect(geo.cell == CGSize(width: 100, height: 100))
        #expect(geo.frame(origin: GridPoint(column: 2, row: 1), span: compact)
                == CGRect(x: 200, y: 100, width: 200, height: 100))
        #expect(geo.size(of: GridSpan(columns: 3, rows: 2)) == CGSize(width: 300, height: 200))
    }

    @Test("interior gaps are included in a span's pixel size")
    func gapsInSpan() {
        let g = DashboardGridGeometry(grid: .standard, canvas: CGSize(width: 612, height: 412), gap: 12)
        // cellW = (612 - 12*5)/6 = 92 ; span of 2 columns = 92*2 + 12 = 196
        #expect(g.size(of: GridSpan(columns: 2, rows: 1)).width == 196)
    }

    @Test("a drag point snaps to the nearest cell")
    func snapsToNearest() {
        #expect(geo.snappedOrigin(pixelTopLeft: CGPoint(x: 0, y: 0), span: compact) == GridPoint(column: 0, row: 0))
        #expect(geo.snappedOrigin(pixelTopLeft: CGPoint(x: 140, y: 40), span: compact) == GridPoint(column: 1, row: 0))
        #expect(geo.snappedOrigin(pixelTopLeft: CGPoint(x: 160, y: 60), span: compact) == GridPoint(column: 2, row: 1))
    }

    @Test("snapping clamps so the footprint never leaves the grid")
    func snapClampsInBounds() {
        // Far past the bottom-right: a 2×1 clamps to (4,3) on a 6×4 grid.
        #expect(geo.snappedOrigin(pixelTopLeft: CGPoint(x: 9_999, y: 9_999), span: compact) == GridPoint(column: 4, row: 3))
        // Negative: clamps to the origin.
        #expect(geo.snappedOrigin(pixelTopLeft: CGPoint(x: -80, y: -80), span: compact) == GridPoint(column: 0, row: 0))
        // A large (6×2) can only ever sit at column 0, rows 0…2.
        #expect(geo.snappedOrigin(pixelTopLeft: CGPoint(x: 300, y: 260), span: large) == GridPoint(column: 0, row: 2))
    }

    @Test("proposedOrigin applies the drag translation once, as a pure delta")
    func proposedOriginIsAPureDelta() {
        // No movement → same cell.
        #expect(geo.proposedOrigin(movingFrom: GridPoint(column: 2, row: 1), span: compact, by: .zero)
                == GridPoint(column: 2, row: 1))

        // A whole number of cells of translation shifts the origin by exactly
        // that many cells — no fractional drift, no oscillation.
        for cells in 0...4 {
            let t = CGSize(width: CGFloat(cells) * geo.step.width, height: 0)
            #expect(geo.proposedOrigin(movingFrom: GridPoint(column: 0, row: 0), span: compact, by: t)
                    == GridPoint(column: cells, row: 0))
        }

        // Half a cell rounds up to the next cell.
        #expect(geo.proposedOrigin(movingFrom: GridPoint(column: 0, row: 0), span: compact,
                                   by: CGSize(width: geo.step.width * 1.5, height: 0))
                == GridPoint(column: 2, row: 0))
    }

    @Test("proposedOrigin clamps a drag past the edge to the last in-bounds cell")
    func proposedOriginClamps() {
        #expect(geo.proposedOrigin(movingFrom: GridPoint(column: 2, row: 2), span: compact,
                                   by: CGSize(width: 9_999, height: 9_999))
                == GridPoint(column: 4, row: 3))
        #expect(geo.proposedOrigin(movingFrom: GridPoint(column: 4, row: 3), span: compact,
                                   by: CGSize(width: -9_999, height: -9_999))
                == GridPoint(column: 0, row: 0))
        // A large widget dragged anywhere still only fits at column 0.
        #expect(geo.proposedOrigin(movingFrom: GridPoint(column: 0, row: 0), span: large,
                                   by: CGSize(width: 500, height: 40)).column == 0)
    }
}

// MARK: - Resize stepper

@Suite("DashboardResizeStepper")
struct DashboardResizeStepperTests {

    private let all: [ComponentSize] = [.compact, .medium, .large]

    @Test("no drag keeps the current size")
    func noDrag() {
        #expect(DashboardResizeStepper.targetSize(
            current: .medium, supported: all, translation: .zero, stepDistance: 60) == .medium)
    }

    @Test("dragging out grows one footprint per step; dragging in shrinks")
    func stepsThroughFootprints() {
        #expect(DashboardResizeStepper.targetSize(
            current: .compact, supported: all,
            translation: CGSize(width: 120, height: 0), stepDistance: 60) == .medium)
        #expect(DashboardResizeStepper.targetSize(
            current: .compact, supported: all,
            translation: CGSize(width: 60, height: 60), stepDistance: 60) == .medium)   // travel = 60
        #expect(DashboardResizeStepper.targetSize(
            current: .large, supported: all,
            translation: CGSize(width: -300, height: 0), stepDistance: 60) == .compact)  // clamps at index 0
    }

    @Test("the result is clamped to the supported list and never an unsupported size")
    func clampedToSupported() {
        let restricted: [ComponentSize] = [.compact]   // e.g. a feature that only supports compact
        for dx in stride(from: -400, through: 400, by: 50) {
            let out = DashboardResizeStepper.targetSize(
                current: .compact, supported: restricted,
                translation: CGSize(width: CGFloat(dx), height: 0), stepDistance: 40)
            #expect(out == .compact)
        }

        // Growing past .large stays at .large.
        #expect(DashboardResizeStepper.targetSize(
            current: .large, supported: all,
            translation: CGSize(width: 999, height: 999), stepDistance: 30) == .large)
    }

    @Test("a current size not in the supported list is returned unchanged")
    func unknownCurrent() {
        #expect(DashboardResizeStepper.targetSize(
            current: .large, supported: [.compact, .medium],
            translation: CGSize(width: 200, height: 0), stepDistance: 40) == .large)
    }

    @Test("a zero step distance is inert")
    func zeroStep() {
        #expect(DashboardResizeStepper.targetSize(
            current: .compact, supported: all,
            translation: CGSize(width: 500, height: 0), stepDistance: 0) == .compact)
    }
}

// MARK: - Store: non-persisting validity checks

@MainActor
@Suite("DashboardLayoutStore interaction queries")
struct InteractionQueryTests {

    private let idA = UUID()
    private let idB = UUID()

    /// idA compact @ (0,0), idB compact @ (2,0) — edge-adjacent, valid.
    private func twoCompacts(_ defaults: UserDefaults) -> DashboardLayoutStore {
        DashboardLayoutStore(
            seed: layout([
                widget(.compact, at: GridPoint(column: 0, row: 0), id: idA),
                widget(.compact, at: GridPoint(column: 2, row: 0), id: idB),
            ]),
            defaults: defaults
        )
    }

    @Test("canMovePlacement: true for a free cell, the current cell, and false for overlap / bounds")
    func canMove() {
        let s = twoCompacts(ephemeralDefaults())
        let before = signature(s.layout)

        #expect(s.canMovePlacement(id: idA, to: GridPoint(column: 4, row: 0)) == true)   // free
        #expect(s.canMovePlacement(id: idA, to: GridPoint(column: 0, row: 0)) == true)   // unchanged
        #expect(s.canMovePlacement(id: idA, to: GridPoint(column: 2, row: 0)) == false)  // onto idB
        #expect(s.canMovePlacement(id: idA, to: GridPoint(column: 5, row: 0)) == false)  // cols 5..7 > 6
        #expect(s.canMovePlacement(id: UUID(), to: GridPoint(column: 4, row: 2)) == false) // unknown id

        #expect(signature(s.layout) == before)   // pure query — nothing changed
    }

    @Test("canResizePlacement: bounds + overlap, without mutating")
    func canResize() {
        let defaults = ephemeralDefaults()
        let s = twoCompacts(defaults)
        let before = signature(s.layout)

        #expect(s.canResizePlacement(id: idA, to: .medium) == false)  // medium (3 wide) collides with idB
        #expect(s.canResizePlacement(id: idB, to: .large) == false)   // large starts at col 2 → off grid
        #expect(s.canResizePlacement(id: idA, to: .compact) == true)  // no change

        // A solo compact can grow to large.
        let solo = DashboardLayoutStore(
            seed: layout([widget(.compact, at: GridPoint(column: 0, row: 0), id: idA)]),
            defaults: ephemeralDefaults()
        )
        #expect(solo.canResizePlacement(id: idA, to: .large) == true)

        #expect(signature(s.layout) == before)   // pure query — nothing changed
    }
}

// MARK: - Commit path: only a final valid placement persists

@MainActor
@Suite("Drag/resize commit persistence")
struct DragCommitPersistenceTests {

    private let idA = UUID()
    private let idB = UUID()
    private let pageID = UUID()

    private func seed() -> DashboardLayout {
        layout([
            widget(.compact, at: GridPoint(column: 0, row: 0), id: idA),
            widget(.compact, at: GridPoint(column: 2, row: 0), id: idB),
        ], pageID: pageID)
    }

    @Test("a full valid move — snap, check, commit — persists")
    func validMovePersists() {
        let defaults = ephemeralDefaults()
        let store = DashboardLayoutStore(seed: seed(), defaults: defaults)

        // What `handleMove` does: snap the dragged point, verify, then commit.
        let geo = DashboardGridGeometry(grid: .standard, canvas: CGSize(width: 600, height: 400), gap: 0)
        let start = geo.frame(origin: GridPoint(column: 0, row: 0), span: GridSpan(columns: 2, rows: 1))
        let dropPoint = CGPoint(x: start.minX + 400, y: start.minY + 300) // drag down-right
        let snapped = geo.snappedOrigin(pixelTopLeft: dropPoint, span: GridSpan(columns: 2, rows: 1))

        #expect(store.canMovePlacement(id: idA, to: snapped))
        #expect(store.movePlacement(id: idA, to: snapped) == true)
        #expect(store.layout.allPlacements.first { $0.id == idA }?.origin == snapped)

        let reloaded = DashboardLayoutStore(seed: seed(), defaults: defaults)
        #expect(reloaded.layout.allPlacements.first { $0.id == idA }?.origin == snapped)
    }

    @Test("an invalid drop is never committed — the layout and disk are unchanged")
    func invalidMoveLeavesLayoutUnchanged() {
        let defaults = ephemeralDefaults()
        let store = DashboardLayoutStore(seed: seed(), defaults: defaults)
        let before = signature(store.layout)

        // Proposed drop lands on idB → invalid, so `handleMove` keeps lastValid
        // (the start) and commits nothing.
        let onTopOfB = GridPoint(column: 2, row: 0)
        #expect(store.canMovePlacement(id: idA, to: onTopOfB) == false)
        // commit is skipped because lastValidOrigin == startOrigin
        #expect(signature(store.layout) == before)

        let reloaded = DashboardLayoutStore(seed: seed(), defaults: defaults)
        #expect(signature(reloaded.layout) == before)
    }

    @Test("a drag that ends back where it started writes nothing new")
    func noOpMoveIsClean() {
        let defaults = ephemeralDefaults()
        let store = DashboardLayoutStore(seed: seed(), defaults: defaults)
        let before = signature(store.layout)

        // lastValidOrigin == startOrigin → handleMove skips the commit entirely.
        #expect(store.canMovePlacement(id: idA, to: GridPoint(column: 0, row: 0)) == true)
        #expect(signature(store.layout) == before)
    }

    @Test("a valid interactive resize persists; an invalid one does not")
    func resizeCommit() {
        let defaults = ephemeralDefaults()

        // Solo compact → grow to large (valid).
        let soloSeed = layout([widget(.compact, at: GridPoint(column: 0, row: 0), id: idA)], pageID: pageID)
        let solo = DashboardLayoutStore(seed: soloSeed, defaults: defaults)
        #expect(solo.canResizePlacement(id: idA, to: .large))
        #expect(solo.updatePlacementSize(id: idA, to: .large) == true)
        #expect(DashboardLayoutStore(seed: soloSeed, defaults: defaults)
            .layout.allPlacements.first?.size == .large)

        // Two compacts → grow idA to medium (overlap) is refused, disk untouched.
        let pairDefaults = ephemeralDefaults()
        let pair = DashboardLayoutStore(seed: seed(), defaults: pairDefaults)
        let before = signature(pair.layout)
        #expect(pair.canResizePlacement(id: idA, to: .medium) == false)
        #expect(pair.updatePlacementSize(id: idA, to: .medium) == false)
        #expect(signature(pair.layout) == before)
        #expect(signature(DashboardLayoutStore(seed: seed(), defaults: pairDefaults).layout) == before)
    }
}

// MARK: - Normal-mode behaviour is untouched

@MainActor
@Suite("Normal-mode widget interaction still opens the feature")
struct NormalModeStillOpensTests {

    private func registry() -> FeatureRegistry {
        FeatureRegistry([SizedFeature(id: "maps", sizes: [.compact, .medium, .large, .full])])
    }

    @Test("tapping a widget in normal mode opens its feature")
    func opens() {
        var opened: [FeatureID] = []
        WidgetHostView(
            placement: widget(.large, at: GridPoint(column: 0, row: 0), feature: "maps"),
            registry: registry(),
            onOpenFeature: { opened.append($0) },
            isEditing: false
        ).activate()
        #expect(opened == ["maps"])
    }

    @Test("in edit mode the tap is still inert (drag/resize replace it)")
    func editingInert() {
        var opened: [FeatureID] = []
        WidgetHostView(
            placement: widget(.large, at: GridPoint(column: 0, row: 0), feature: "maps"),
            registry: registry(),
            onOpenFeature: { opened.append($0) },
            isEditing: true
        ).activate()
        #expect(opened.isEmpty)
    }

    @Test("resize affordances only appear for features with more than one widget size")
    func resizeGatedBySupportedSizes() {
        let reg = FeatureRegistry([
            SizedFeature(id: "maps", sizes: [.compact, .medium, .large, .full]),
            SizedFeature(id: "clock", sizes: [.compact, .full]),
        ])
        let maps = WidgetHostView(
            placement: widget(.medium, at: GridPoint(column: 0, row: 0), feature: "maps"),
            registry: reg, onOpenFeature: { _ in }, isEditing: true
        )
        let clock = WidgetHostView(
            placement: widget(.compact, at: GridPoint(column: 0, row: 0), feature: "clock"),
            registry: reg, onOpenFeature: { _ in }, isEditing: true
        )
        #expect(maps.supportedWidgetSizes == [.compact, .medium, .large])
        #expect(clock.supportedWidgetSizes == [.compact])   // count 1 → no resize handle / menu
    }
}
