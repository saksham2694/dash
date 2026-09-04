//
//  VisualRefinementTests.swift
//  DashTests
//
//  M5.5.2b — the CarPlay visual-refinement pass. These are not screenshot tests;
//  they lock the deterministic assumptions the refined shell now depends on:
//
//    • the rail status cluster stacks time / phone / GPS / battery in that order,
//      and the time renders on a single line,
//    • registered features carry a coherent, intentional icon identity, and the
//      not-yet-built ones (Music, Speedometer) advertise no dashboard widget,
//    • the dashboard grid geometry supports the weighted ~56 / 44 column split
//      while still tiling "large + 2 medium" / "large + 3 compact" exactly,
//    • the compact Map widget chooses its fields by available width (primary
//      maneuver first, secondary info only when it fits),
//    • the Add-Widget footprint preview matches the real grid span.
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Dash

// MARK: - Sidebar status cluster

@Suite("Sidebar status cluster")
struct SidebarStatusClusterTests {

    @Test("rows stack time → phone → GPS → battery, top to bottom")
    func rowOrder() {
        #expect(DashStatusModel.rowOrder == [.time, .phone, .gps, .battery])
        // Every row is represented exactly once.
        #expect(Set(DashStatusModel.rowOrder).count == DashStatusModel.Row.allCases.count)
    }

    @Test("the time is a single line — no newline in the formatted string")
    func timeIsOneLine() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 4; comps.hour = 9; comps.minute = 41
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let text = DashStatusModel.timeText(date, locale: Locale(identifier: "en_US"))
        #expect(!text.contains("\n"))
        #expect(!text.isEmpty)
    }

    @Test("GPS state maps to a dot colour + short label, and never the lost/active wording is swapped")
    func gpsState() {
        #expect(DashStatusModel.gpsShortLabel(isSignalLost: true, hasFix: false) == "No GPS")
        #expect(DashStatusModel.gpsShortLabel(isSignalLost: false, hasFix: true) == "GPS")
        #expect(DashStatusModel.gpsShortLabel(isSignalLost: false, hasFix: false) == "GPS…")

        #expect(DashStatusModel.gpsColor(isSignalLost: true, hasFix: false) == Color.dashDanger)
        #expect(DashStatusModel.gpsColor(isSignalLost: false, hasFix: true) == Color.dashPositive)
        #expect(DashStatusModel.gpsColor(isSignalLost: false, hasFix: false) == Color.dashTextTertiary)

        #expect(DashStatusModel.gpsLabel(isSignalLost: true, hasFix: false) == "GPS signal lost")
    }
}

// MARK: - Outer shell metrics

@Suite("Shell composition metrics")
struct ShellCompositionMetricTests {

    @Test("the shell is a contained, rounded, inset panel")
    func shellMetrics() {
        #expect(DashMetrics.shellOuterInset > 0)
        #expect(DashMetrics.shellCornerRadius > DashMetrics.controlCornerRadius)
        #expect(DashMetrics.shellContentInset > 0)
    }

    @Test("the dashboard column split favours the left (large) column but stays balanced")
    func columnSplit() {
        let f = DashMetrics.dashboardLeftColumnFraction
        #expect(f > 0.5)
        #expect(f < 0.65)
    }
}

// MARK: - Feature icon identity

@MainActor
@Suite("Feature icon identity")
struct FeatureIconIdentityTests {

    @Test("each registered feature pins an intentional, distinct tint")
    func pinnedTints() {
        let registry = FeatureRegistry.makeDefault()

        func tint(_ id: FeatureID) -> FeatureTint? {
            guard let m = registry.feature(id)?.manifest else { return nil }
            return DashAppIcon.tint(for: m.iconStyle, id: id)
        }

        #expect(tint("maps") == .green)
        #expect(tint("apple-maps") == .blue)
        #expect(tint("music") == .pink)
        #expect(tint("weather") == .teal)
        #expect(tint("speedometer") == .orange)
        #expect(tint("settings") == .graphite)

        // A coherent family: no two share a tint.
        let tints = registry.manifests.map { DashAppIcon.tint(for: $0.iconStyle, id: $0.id) }
        #expect(Set(tints).count == tints.count)
    }

    @Test("the six registered features are present, in the fixed sidebar order, with their real names")
    func sixFeaturesInOrder() {
        let registry = FeatureRegistry.makeDefault()
        #expect(registry.manifests.map(\.id) == ["maps", "apple-maps", "music", "weather", "speedometer", "settings"])
        #expect(registry.manifests.map(\.title) == [
            "Google Maps", "Apple Maps", "Apple Music", "Weather", "Speedometer", "Settings",
        ])
    }

    @Test("each feature names the local icon asset the private build should use")
    func iconAssetIdentifiers() {
        let registry = FeatureRegistry.makeDefault()
        #expect(registry.feature("maps")?.manifest.iconAssetName == "app-icon-google-maps")
        #expect(registry.feature("apple-maps")?.manifest.iconAssetName == "app-icon-apple-maps")
        #expect(registry.feature("music")?.manifest.iconAssetName == "app-icon-apple-music")
        #expect(registry.feature("weather")?.manifest.iconAssetName == "app-icon-weather")
        #expect(registry.feature("speedometer")?.manifest.iconAssetName == "app-icon-speedometer")
        #expect(registry.feature("settings")?.manifest.iconAssetName == "app-icon-settings")
    }

    @Test("every not-yet-built feature advertises no dashboard widget size")
    func placeholdersHaveNoWidgets() {
        let registry = FeatureRegistry.makeDefault()
        for id in ["apple-maps", "music", "weather", "settings"] {
            #expect(registry.feature(id)?.manifest.supportedWidgetSizes.isEmpty == true)
        }
        // …so the Add-Widget picker offers only the real widget features.
        let placeable = DashboardWidgetPickerView.placeableFeatures(registry.manifests).map(\.id)
        #expect(placeable == ["maps", "speedometer"])
    }

    @Test("the Speedometer offers every widget size from one engine")
    func speedometerHasWidgets() {
        let registry = FeatureRegistry.makeDefault()
        let manifest = registry.feature("speedometer")?.manifest
        #expect(manifest?.supportedWidgetSizes == [.compact, .medium, .large])
        #expect(manifest?.supportedSizes.contains(.full) == true)
    }

    @Test("Settings keeps a stable id for a future real SettingsFeature")
    func settingsIdIsStable() {
        #expect(PlaceholderFeature.ID.settings == "settings")
        #expect(FeatureRegistry.makeDefault().feature("settings")?.manifest.title == "Settings")
    }
}

// MARK: - Weighted dashboard geometry

@Suite("Weighted dashboard geometry")
struct WeightedGridGeometryTests {

    private let canvas = CGSize(width: 900, height: 600)

    private func geo(_ fraction: CGFloat) -> DashboardGridGeometry {
        DashboardGridGeometry(grid: .standard, canvas: canvas, gap: 10, leftColumnFraction: fraction)
    }

    @Test("an even fraction keeps the columns equal (unchanged default behaviour)")
    func evenSplit() {
        let g = geo(0.5)
        #expect(g.columnWidth(0) == g.columnWidth(1))
        #expect(abs(g.columnWidth(0) - (canvas.width - 10) / 2) < 0.001)
    }

    @Test("the ~56/44 split makes the left column wider by the right ratio")
    func weightedSplit() {
        let g = geo(0.56)
        let content = canvas.width - 10
        #expect(abs(g.columnWidth(0) - content * 0.56) < 0.001)
        #expect(abs(g.columnWidth(1) - content * 0.44) < 0.001)
        #expect(g.columnWidth(0) > g.columnWidth(1))
        // The two columns + the gap still exactly fill the canvas.
        #expect(abs(g.columnWidth(0) + g.columnWidth(1) + 10 - canvas.width) < 0.001)
    }

    @Test("the right column starts after the wide left column + the gap")
    func columnOrigins() {
        let g = geo(0.56)
        #expect(g.columnX(0) == 0)
        #expect(abs(g.columnX(1) - (g.columnWidth(0) + 10)) < 0.001)
    }

    @Test("large + 2 medium tiles the canvas with no gaps or overlaps (weighted)")
    func largePlusTwoMediumTiling() {
        let g = geo(0.56)
        let grid = DashboardGrid.standard

        let large = g.frame(origin: GridPoint(column: 0, row: 0), span: grid.span(for: .large))
        let top = g.frame(origin: GridPoint(column: 1, row: 0), span: grid.span(for: .medium))
        let bottom = g.frame(origin: GridPoint(column: 1, row: 3), span: grid.span(for: .medium))

        // Left column full height.
        #expect(abs(large.height - canvas.height) < 0.001)
        // Right stack meets in the middle and fills the height.
        #expect(abs(top.maxY + 10 - bottom.minY) < 0.001)
        #expect(abs(bottom.maxY - canvas.height) < 0.001)
        // No horizontal overlap between the columns.
        #expect(large.maxX <= top.minX + 0.001)
    }

    @Test("large + 3 compact stacks three equal thirds in the right column")
    func largePlusThreeCompactTiling() {
        let g = geo(0.56)
        let grid = DashboardGrid.standard
        let rows = [0, 2, 4].map {
            g.frame(origin: GridPoint(column: 1, row: $0), span: grid.span(for: .compact))
        }
        #expect(abs(rows[0].height - rows[1].height) < 0.001)
        #expect(abs(rows[1].height - rows[2].height) < 0.001)
        #expect(abs(rows[0].maxY + 10 - rows[1].minY) < 0.001)
        #expect(abs(rows[2].maxY - canvas.height) < 0.001)
    }

    @Test("a drag still snaps to a valid in-bounds origin under the weighted split")
    func snappingStillClamps() {
        let g = geo(0.56)
        let span = DashboardGrid.standard.span(for: .compact)
        let snapped = g.snappedOrigin(pixelTopLeft: CGPoint(x: 5_000, y: 5_000), span: span)
        #expect(snapped.column == 1)          // clamped to the last column
        #expect(snapped.row == DashboardGrid.standard.rows - span.rows)
    }
}

// MARK: - Compact Map widget field selection

@Suite("Compact Map maneuver layout")
struct MapCompactManeuverLayoutTests {

    @Test("the narrowest width shows only the maneuver icon + turn distance")
    func narrowest() {
        let f = MapCompactManeuverLayout.fields(availableWidth: 120)
        #expect(f.showInstruction == false)
        #expect(f.showTimeAndETA == false)
        #expect(f.showRemainingDistance == false)
    }

    @Test("a little more width adds the turn instruction")
    func addsInstruction() {
        let f = MapCompactManeuverLayout.fields(availableWidth: 220)
        #expect(f.showInstruction)
        #expect(f.showTimeAndETA == false)
    }

    @Test("a medium width adds time + ETA, but not the remaining trip distance")
    func addsTimeAndETA() {
        let f = MapCompactManeuverLayout.fields(availableWidth: 300)
        #expect(f.showInstruction)
        #expect(f.showTimeAndETA)
        #expect(f.showRemainingDistance == false)
    }

    @Test("a wide compact widget shows everything, remaining distance included")
    func widest() {
        let f = MapCompactManeuverLayout.fields(availableWidth: 420)
        #expect(f.showInstruction)
        #expect(f.showTimeAndETA)
        #expect(f.showRemainingDistance)
    }

    @Test("fields only ever grow as width grows — nothing is dropped by widening")
    func monotonic() {
        let widths: [CGFloat] = [80, 160, 200, 260, 320, 360, 500]
        var last = MapCompactManeuverLayout.fields(availableWidth: widths[0])
        for w in widths.dropFirst() {
            let next = MapCompactManeuverLayout.fields(availableWidth: w)
            #expect(!(last.showInstruction && !next.showInstruction))
            #expect(!(last.showTimeAndETA && !next.showTimeAndETA))
            #expect(!(last.showRemainingDistance && !next.showRemainingDistance))
            last = next
        }
    }
}

// MARK: - Add-Widget footprint preview

@Suite("Add-Widget footprint preview")
struct WidgetFootprintPreviewTests {

    @Test("the preview footprint is exactly the grid span for each widget size")
    func matchesGridSpan() {
        for size in ComponentSize.widgetSizes {
            #expect(WidgetFootprintPreview.span(for: size) == DashboardGrid.standard.span(for: size))
        }
    }

    @Test("compact = 1×2, medium = 1×3, large = 1×6 on the 2×6 grid")
    func concreteFootprints() {
        #expect(WidgetFootprintPreview.span(for: .compact) == GridSpan(columns: 1, rows: 2))
        #expect(WidgetFootprintPreview.span(for: .medium) == GridSpan(columns: 1, rows: 3))
        #expect(WidgetFootprintPreview.span(for: .large) == GridSpan(columns: 1, rows: 6))
    }
}
