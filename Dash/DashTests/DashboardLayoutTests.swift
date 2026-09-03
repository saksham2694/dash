//
//  DashboardLayoutTests.swift
//  DashTests
//
//  The M5.2.0 dashboard-layout foundation: the SDK-neutral model
//  (`DashboardLayout` / `DashboardPage` / `WidgetPlacement`), the grid math
//  (`DashboardGrid` / `GridRect`), and `DashboardLayoutValidator`.
//

import Foundation
import SwiftUI
import Testing
@testable import Dash

// MARK: - Fixtures

/// Minimal `DashFeature` for registry-aware validation tests.
@MainActor
private final class TestFeature: DashFeature {
    let manifest: FeatureManifest
    init(id: FeatureID, sizes: Set<ComponentSize> = [.compact, .medium, .large, .full]) {
        self.manifest = FeatureManifest(
            id: id, title: id, symbolName: "app.fill",
            supportedSizes: sizes, defaultSize: sizes.contains(.large) ? .large : sizes.first!
        )
    }
    func makeFullScreenView() -> AnyView { AnyView(EmptyView()) }
    func makeComponentView(size: ComponentSize) -> AnyView { AnyView(EmptyView()) }
}

private func placement(
    _ feature: FeatureID = "maps",
    _ size: ComponentSize = .compact,
    at origin: GridPoint = GridPoint(column: 0, row: 0),
    id: UUID = UUID()
) -> WidgetPlacement {
    WidgetPlacement(id: id, featureID: feature, size: size, origin: origin)
}

// MARK: - Model

@Suite("DashboardLayout model")
struct DashboardLayoutModelTests {

    @Test("a placement gets a unique id by default; an explicit id is kept")
    func placementIdentity() {
        let a = WidgetPlacement(featureID: "maps", size: .compact, origin: .init(column: 0, row: 0))
        let b = WidgetPlacement(featureID: "maps", size: .compact, origin: .init(column: 0, row: 0))
        #expect(a.id != b.id)

        let fixed = UUID()
        #expect(WidgetPlacement(id: fixed, featureID: "maps", size: .compact, origin: .init(column: 0, row: 0)).id == fixed)
    }

    @Test("the starter layout is the single Dashboard page; page access is bounds-checked")
    func pageAccess() {
        let layout = DashboardLayout.starter(featureID: "maps")
        #expect(layout.pageCount == 1)
        #expect(layout.page(at: 0) != nil)
        #expect(layout.page(at: 1) == nil)
        #expect(layout.page(at: -1) == nil)
        #expect(layout.allPlacements.count == 3)
    }

    @Test("empty vs non-empty")
    func emptiness() {
        #expect(DashboardLayout(pages: []).isEmpty)
        #expect(DashboardLayout(pages: [DashboardPage()]).isEmpty)
        #expect(!DashboardLayout.starter(featureID: "maps").isEmpty)
    }

    @Test("round-trips through Codable with identity preserved")
    func codableRoundTrip() throws {
        let original = DashboardLayout.starter(featureID: "maps")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DashboardLayout.self, from: data)
        #expect(decoded == original)
        #expect(decoded.allPlacements.map(\.id) == original.allPlacements.map(\.id))
    }
}

// MARK: - Grid

@Suite("DashboardGrid")
struct DashboardGridTests {

    let grid = DashboardGrid.standard

    @Test("widget sizes map to cell spans; full spans the whole grid")
    func spans() {
        #expect(grid.span(for: .compact) == GridSpan(columns: 2, rows: 1))
        #expect(grid.span(for: .medium) == GridSpan(columns: 3, rows: 2))
        #expect(grid.span(for: .large) == GridSpan(columns: 6, rows: 2))
        #expect(grid.span(for: .full) == GridSpan(columns: 6, rows: 4))
    }

    @Test("contains checks the full footprint")
    func bounds() {
        #expect(grid.contains(grid.rect(for: placement("maps", .large, at: .init(column: 0, row: 0)))))
        #expect(grid.contains(grid.rect(for: placement("maps", .medium, at: .init(column: 3, row: 2)))))
        // large (6×2) starting at row 3 → maxRow 5 > 4
        #expect(!grid.contains(grid.rect(for: placement("maps", .large, at: .init(column: 0, row: 3)))))
        // compact (2×1) starting at column 5 → maxColumn 7 > 6
        #expect(!grid.contains(grid.rect(for: placement("maps", .compact, at: .init(column: 5, row: 0)))))
    }

    @Test("intersects is true only when cells are shared")
    func intersection() {
        let a = GridRect(origin: .init(column: 0, row: 0), span: .init(columns: 2, rows: 1))
        let b = GridRect(origin: .init(column: 1, row: 0), span: .init(columns: 2, rows: 1))
        let c = GridRect(origin: .init(column: 2, row: 0), span: .init(columns: 2, rows: 1))
        #expect(a.intersects(b))
        #expect(!a.intersects(c)) // edge-adjacent, not overlapping
        #expect(b.intersects(c))
    }
}

// MARK: - Validation

@Suite("DashboardLayoutValidator (structural)")
struct DashboardLayoutValidatorStructuralTests {

    let grid = DashboardGrid.standard

    @Test("a clean layout has no issues")
    func clean() {
        let layout = DashboardLayout.starter(featureID: "maps")
        #expect(DashboardLayoutValidator.validate(layout, grid: grid).isEmpty)
        #expect(DashboardLayoutValidator.isStructurallyValid(layout, grid: grid))
    }

    @Test("overlapping placements on a page are reported")
    func overlap() {
        let a = placement("maps", .compact, at: .init(column: 0, row: 0))
        let b = placement("maps", .compact, at: .init(column: 1, row: 0))
        let layout = DashboardLayout(pages: [DashboardPage(placements: [a, b])])
        let issues = DashboardLayoutValidator.validate(layout, grid: grid)
        #expect(issues.contains(.overlap(a.id, b.id)))
    }

    @Test("placements on different pages never collide")
    func noCrossPageOverlap() {
        let a = placement("maps", .large, at: .init(column: 0, row: 0))
        let b = placement("maps", .large, at: .init(column: 0, row: 0))
        let layout = DashboardLayout(pages: [
            DashboardPage(placements: [a]),
            DashboardPage(placements: [b]),
        ])
        #expect(DashboardLayoutValidator.validate(layout, grid: grid).isEmpty)
    }

    @Test("a widget past the grid edge is out of bounds")
    func outOfBounds() {
        let p = placement("maps", .large, at: .init(column: 0, row: 3))
        let layout = DashboardLayout(pages: [DashboardPage(placements: [p])])
        #expect(DashboardLayoutValidator.validate(layout, grid: grid).contains(.outOfBounds(placementID: p.id)))
    }

    @Test("a full-size placement is not a valid widget")
    func fullSizeRejected() {
        let p = placement("maps", .full, at: .init(column: 0, row: 0))
        let layout = DashboardLayout(pages: [DashboardPage(placements: [p])])
        #expect(DashboardLayoutValidator.validate(layout, grid: grid).contains(.notAWidgetSize(placementID: p.id, size: .full)))
    }

    @Test("a duplicate placement id is reported once")
    func duplicateID() {
        let shared = UUID()
        let a = placement("maps", .compact, at: .init(column: 0, row: 0), id: shared)
        let b = placement("maps", .compact, at: .init(column: 3, row: 0), id: shared)
        let layout = DashboardLayout(pages: [DashboardPage(placements: [a, b])])
        let issues = DashboardLayoutValidator.validate(layout, grid: grid)
        #expect(issues.filter { $0 == .duplicatePlacementID(shared) }.count == 1)
    }
}

@MainActor
@Suite("DashboardLayoutValidator (registry-aware)")
struct DashboardLayoutValidatorRegistryTests {

    let grid = DashboardGrid.standard

    @Test("an unknown feature id is reported")
    func unknownFeature() {
        let registry = FeatureRegistry([TestFeature(id: "maps")])
        let p = placement("ghost", .compact, at: .init(column: 0, row: 0))
        let layout = DashboardLayout(pages: [DashboardPage(placements: [p])])
        let issues = DashboardLayoutValidator.validate(layout, grid: grid, registry: registry)
        #expect(issues.contains(.unknownFeature(placementID: p.id, featureID: "ghost")))
    }

    @Test("a size the feature does not support is reported")
    func unsupportedSize() {
        let registry = FeatureRegistry([TestFeature(id: "maps", sizes: [.large, .full])])
        let p = placement("maps", .compact, at: .init(column: 0, row: 0))
        let layout = DashboardLayout(pages: [DashboardPage(placements: [p])])
        let issues = DashboardLayoutValidator.validate(layout, grid: grid, registry: registry)
        #expect(issues.contains(.unsupportedSize(placementID: p.id, featureID: "maps", size: .compact)))
    }

    @Test("the shipped starter layout is valid against the real registry")
    func starterLayoutValid() {
        let registry = FeatureRegistry.makeDefault()
        let layout = DashboardLayout.starter(featureID: MapFeature.id)
        #expect(DashboardLayoutValidator.validate(layout, grid: grid, registry: registry).isEmpty)
    }
}
