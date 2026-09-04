//
//  DashboardCompositionTests.swift
//  DashTests
//
//  M5.5.2a — the redesigned Dashboard canvas: a 2-column, 6-row grid whose
//  intended compositions ("large + 2 medium", "large + 3 compact") tile the
//  whole canvas with no half-width voids.
//

import Foundation
import Testing
@testable import Dash

@Suite("Dashboard canvas compositions")
struct DashboardCompositionTests {

    private let grid = DashboardGrid.standard   // 2 × 6

    private func layout(_ placements: [WidgetPlacement]) -> DashboardLayout {
        DashboardLayout(pages: [DashboardPage(placements: placements)])
    }

    /// The number of grid cells the placements cover (they must not overlap for
    /// this to equal the tiled area).
    private func coveredCells(_ layout: DashboardLayout) -> Int {
        layout.allPlacements.reduce(0) { sum, placement in
            let span = grid.span(for: placement.size)
            return sum + span.columns * span.rows
        }
    }

    @Test("the grid is two columns and six rows")
    func gridShape() {
        #expect(grid.columns == 2)
        #expect(grid.rows == 6)
    }

    @Test("large + 2 medium is valid and tiles the whole canvas")
    func largePlusTwoMedium() {
        let l = layout([
            WidgetPlacement(featureID: "maps", size: .large,  origin: GridPoint(column: 0, row: 0)),
            WidgetPlacement(featureID: "maps", size: .medium, origin: GridPoint(column: 1, row: 0)),
            WidgetPlacement(featureID: "maps", size: .medium, origin: GridPoint(column: 1, row: 3)),
        ])
        #expect(DashboardLayoutValidator.isStructurallyValid(l, grid: grid))
        #expect(coveredCells(l) == grid.columns * grid.rows)   // no leftover space
    }

    @Test("large + 3 compact is valid and tiles the whole canvas")
    func largePlusThreeCompact() {
        let l = layout([
            WidgetPlacement(featureID: "maps", size: .large,   origin: GridPoint(column: 0, row: 0)),
            WidgetPlacement(featureID: "maps", size: .compact, origin: GridPoint(column: 1, row: 0)),
            WidgetPlacement(featureID: "maps", size: .compact, origin: GridPoint(column: 1, row: 2)),
            WidgetPlacement(featureID: "maps", size: .compact, origin: GridPoint(column: 1, row: 4)),
        ])
        #expect(DashboardLayoutValidator.isStructurallyValid(l, grid: grid))
        #expect(coveredCells(l) == grid.columns * grid.rows)
    }

    @Test("the shipped starter is the large + 2 medium composition")
    func starterIsLargePlusTwoMedium() {
        let starter = DashboardLayout.starter(featureID: MapFeature.id)
        let sizes = starter.allPlacements.map(\.size).sorted { $0.rawValue < $1.rawValue }
        #expect(sizes == [.large, .medium, .medium].sorted { $0.rawValue < $1.rawValue })
        #expect(DashboardLayoutValidator.isStructurallyValid(starter, grid: grid))
        #expect(coveredCells(starter) == grid.columns * grid.rows)
    }

    @Test("a widget is always exactly one column wide")
    func widgetsAreOneColumnWide() {
        for size in ComponentSize.widgetSizes {
            #expect(grid.span(for: size).columns == 1)
        }
    }

    @Test("a half-filled column leaves the other column empty (a void the editor should discourage) but is still structurally valid")
    func partialFillStillValid() {
        // One compact alone — the rest of the canvas is empty. Not a great
        // composition, but the model must not forbid it.
        let l = layout([
            WidgetPlacement(featureID: "maps", size: .compact, origin: GridPoint(column: 0, row: 0)),
        ])
        #expect(DashboardLayoutValidator.isStructurallyValid(l, grid: grid))
        #expect(coveredCells(l) < grid.columns * grid.rows)
    }
}
