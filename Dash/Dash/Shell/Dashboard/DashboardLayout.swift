//
//  DashboardLayout.swift
//  Dash
//
//  The persisted arrangement of the widget dashboard: ordered pages, each an
//  ordered list of widget placements. SDK-neutral and SwiftUI-free — plain
//  `Codable` value types referencing only `FeatureID` / `ComponentSize` /
//  `GridPoint`.
//
//  This owns *arrangement*, not runtime feature state (M5 proposal §8, §14).
//  Nothing here knows how a widget renders — that is `DashFeature`.
//
//  The persistence envelope + schema version live in `DashboardLayoutStore`, not
//  on this model.
//

import Foundation

/// One widget on a dashboard page.
nonisolated struct WidgetPlacement: Identifiable, Equatable, Sendable, Codable {

    /// Stable identity for this placement — survives reorder / resize and keys
    /// SwiftUI `ForEach`. Assigned once.
    let id: UUID

    /// Which feature fills this widget (see `FeatureRegistry`).
    var featureID: FeatureID

    /// The footprint the shell should give it. A dashboard placement is always
    /// a widget size — `.full` is invalid here (see `DashboardLayoutValidator`).
    var size: ComponentSize

    /// Top-left cell on the grid.
    var origin: GridPoint

    init(id: UUID = UUID(), featureID: FeatureID, size: ComponentSize, origin: GridPoint) {
        self.id = id
        self.featureID = featureID
        self.size = size
        self.origin = origin
    }
}

/// One page of the widget dashboard.
nonisolated struct DashboardPage: Identifiable, Equatable, Sendable, Codable {

    let id: UUID
    var placements: [WidgetPlacement]

    init(id: UUID = UUID(), placements: [WidgetPlacement] = []) {
        self.id = id
        self.placements = placements
    }
}

/// The whole dashboard — an ordered list of pages.
nonisolated struct DashboardLayout: Equatable, Sendable, Codable {

    var pages: [DashboardPage]

    init(pages: [DashboardPage]) {
        self.pages = pages
    }

    var pageCount: Int { pages.count }

    var isEmpty: Bool { pages.allSatisfy { $0.placements.isEmpty } }

    /// The page at `index`, or `nil` when out of range.
    func page(at index: Int) -> DashboardPage? {
        pages.indices.contains(index) ? pages[index] : nil
    }

    /// Every placement, flattened across pages (in page then placement order).
    var allPlacements: [WidgetPlacement] {
        pages.flatMap(\.placements)
    }
}

extension DashboardLayout {

    /// A starter layout: the **one** Dashboard page, one feature shown at three
    /// sizes — enough to show the grid handling multiple footprints and
    /// positions. The caller passes the feature id so `Shell/` stays
    /// feature-agnostic (`DashApp` supplies `MapFeature.id`).
    ///
    /// There is exactly one Dashboard page — the product does not paginate the
    /// Dashboard. The page model is retained only for a possible future
    /// customisation feature.
    ///
    /// Coordinates assume `DashboardGrid.standard` (6 × 4).
    static func starter(featureID: FeatureID) -> DashboardLayout {
        DashboardLayout(pages: [
            DashboardPage(placements: [
                WidgetPlacement(featureID: featureID, size: .large,   origin: GridPoint(column: 0, row: 0)),
                WidgetPlacement(featureID: featureID, size: .medium,  origin: GridPoint(column: 0, row: 2)),
                WidgetPlacement(featureID: featureID, size: .compact, origin: GridPoint(column: 3, row: 2)),
            ]),
        ])
    }
}
