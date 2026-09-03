//
//  DashboardLayoutEditor.swift
//  Dash
//
//  Pure, SDK-neutral transforms that produce a *new* `DashboardLayout` from an
//  existing one plus one edit operation. No SwiftUI, no persistence, no
//  validation — the caller (`DashboardLayoutStore`) validates the result with
//  `DashboardLayoutValidator` and only then persists.
//
//  This is the smallest customization vocabulary the Dashboard editor needs:
//    • remove a placement by id
//    • change a placement's size by id
//    • add a placement to a page
//    • move a placement (its grid origin) by id  — the clean representation of
//      "move / reorder"; the actual drag interaction is a later milestone.
//    • find the first free grid slot for a new widget (M5.4.2) — so the editor
//      never asks the user to pick coordinates.
//
//  Each transform is total: an id / page that doesn't exist yields the layout
//  unchanged, so the store can treat "no-op" and "rejected" uniformly.
//

import Foundation

nonisolated enum DashboardLayoutEditor {

    /// Remove the placement with `placementID` from whichever page holds it.
    static func removing(placementID: UUID, from layout: DashboardLayout) -> DashboardLayout {
        mapPages(layout) { page in
            page.placements.removeAll { $0.id == placementID }
        }
    }

    /// Set the `size` of the placement with `placementID`. Origin is unchanged —
    /// a resulting overlap / out-of-bounds is the validator's job to catch.
    static func settingSize(
        of placementID: UUID,
        to size: ComponentSize,
        in layout: DashboardLayout
    ) -> DashboardLayout {
        mapPlacement(layout, placementID) { $0.size = size }
    }

    /// Move the placement with `placementID` to a new grid `origin`.
    static func moving(
        placementID: UUID,
        to origin: GridPoint,
        in layout: DashboardLayout
    ) -> DashboardLayout {
        mapPlacement(layout, placementID) { $0.origin = origin }
    }

    /// Append `placement` to the page at `pageIndex`. Out-of-range → unchanged.
    static func adding(
        _ placement: WidgetPlacement,
        toPageAt pageIndex: Int,
        in layout: DashboardLayout
    ) -> DashboardLayout {
        guard layout.pages.indices.contains(pageIndex) else { return layout }
        var pages = layout.pages
        pages[pageIndex].placements.append(placement)
        return DashboardLayout(pages: pages)
    }

    /// The first grid position a widget of `size` fits at on the page at
    /// `pageIndex` — scanned **deterministically from the top-left, left-to-right
    /// within a row, then down to the next row** — without overlapping an
    /// existing placement or leaving `grid`. `nil` when there is no room (or
    /// `size` isn't a widget size, or the page doesn't exist).
    static func firstFreeOrigin(
        for size: ComponentSize,
        onPageAt pageIndex: Int,
        in layout: DashboardLayout,
        grid: DashboardGrid
    ) -> GridPoint? {
        guard size.isWidget, let page = layout.page(at: pageIndex) else { return nil }

        let span = grid.span(for: size)
        guard span.columns <= grid.columns, span.rows <= grid.rows else { return nil }

        let occupied = page.placements.map { grid.rect(for: $0) }

        for row in 0 ... (grid.rows - span.rows) {
            for column in 0 ... (grid.columns - span.columns) {
                let candidate = GridRect(origin: GridPoint(column: column, row: row), span: span)
                if occupied.allSatisfy({ !$0.intersects(candidate) }) {
                    return candidate.origin
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    /// Rebuild `layout` applying `edit` to each page's placement array.
    private static func mapPages(
        _ layout: DashboardLayout,
        _ edit: (inout DashboardPage) -> Void
    ) -> DashboardLayout {
        var pages = layout.pages
        for index in pages.indices {
            edit(&pages[index])
        }
        return DashboardLayout(pages: pages)
    }

    /// Rebuild `layout` applying `edit` to the single placement matching `id`.
    private static func mapPlacement(
        _ layout: DashboardLayout,
        _ id: UUID,
        _ edit: (inout WidgetPlacement) -> Void
    ) -> DashboardLayout {
        mapPages(layout) { page in
            guard let i = page.placements.firstIndex(where: { $0.id == id }) else { return }
            edit(&page.placements[i])
        }
    }
}
