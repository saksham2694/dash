//
//  DashboardGridGeometry.swift
//  Dash
//
//  The one place the dashboard's cell math (`DashboardGrid`, in cells) meets
//  pixels. Pure and SDK-neutral (CoreGraphics only, no SwiftUI): it maps a
//  `DashboardGrid` onto a pixel canvas so `DashboardSpaceView` can both lay
//  widgets out and, in edit mode, **snap a drag to a `GridPoint`**.
//
//  Kept out of `DashboardGrid` so that file stays purely cell-count math, and
//  out of `DashboardSpaceView` so the conversion is trivially unit-testable.
//
//  M5.5.2b: the two-column canvas uses a **weighted split** — the left column is
//  wider than the right (`leftColumnFraction`, ~0.56) so the large Map widget
//  visually dominates and the supporting right stack stays compact, matching the
//  CarPlay reference. Rows stay uniform. Equal columns (`0.5`) remain the
//  default so callers / tests that don't care get the old behaviour.
//
//  Also here: `DashboardResizeStepper`, the pure "which supported size does this
//  resize drag land on" helper — so interactive resize snaps through the
//  existing `ComponentSize` footprints, never arbitrary pixel dimensions.
//

import CoreGraphics

nonisolated struct DashboardGridGeometry: Equatable, Sendable {

    let grid: DashboardGrid
    let canvas: CGSize
    let gap: CGFloat

    /// Fraction of the horizontal space (gaps excluded) the **left** column
    /// takes on a two-column grid. `0.5` = equal columns. Ignored when the grid
    /// isn't exactly two columns.
    let leftColumnFraction: CGFloat

    init(grid: DashboardGrid, canvas: CGSize, gap: CGFloat, leftColumnFraction: CGFloat = 0.5) {
        self.grid = grid
        self.canvas = canvas
        self.gap = gap
        self.leftColumnFraction = min(0.8, max(0.2, leftColumnFraction))
    }

    /// The total width available to columns (canvas minus the inter-column gaps).
    private var contentWidth: CGFloat {
        max(0, canvas.width - gap * CGFloat(max(0, grid.columns - 1)))
    }

    /// Whether the weighted split applies (two columns and a non-even fraction).
    private var isWeighted: Bool {
        grid.columns == 2 && abs(leftColumnFraction - 0.5) > 0.0001
    }

    /// One column's pixel width.
    func columnWidth(_ index: Int) -> CGFloat {
        guard grid.columns > 0 else { return 0 }
        guard isWeighted else { return contentWidth / CGFloat(grid.columns) }
        return index == 0
            ? contentWidth * leftColumnFraction
            : contentWidth * (1 - leftColumnFraction)
    }

    /// The x of a column's left edge on the canvas.
    func columnX(_ index: Int) -> CGFloat {
        var x: CGFloat = 0
        for i in 0..<max(0, index) {
            x += columnWidth(i) + gap
        }
        return x
    }

    /// One row's pixel height (rows are always uniform).
    var rowHeight: CGFloat {
        guard grid.rows > 0 else { return 0 }
        let h = (canvas.height - gap * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
        return max(0, h)
    }

    /// One cell's pixel size — column 0's width (the reference column) and a row.
    /// Kept for drag-sensitivity math and callers that want a representative
    /// unit; per-column widths come from `columnWidth(_:)`.
    var cell: CGSize {
        CGSize(width: columnWidth(0), height: rowHeight)
    }

    /// The distance from one row's top to the next (row + gap). Horizontal step
    /// is column-dependent, so callers snapping x use `columnX(_:)` directly.
    var step: CGSize {
        CGSize(width: columnWidth(0) + gap, height: rowHeight + gap)
    }

    /// The pixel width a span starting at `column` occupies (spanned column
    /// widths + interior gaps).
    func width(of span: GridSpan, startingAt column: Int) -> CGFloat {
        guard span.columns > 0 else { return 0 }
        var w: CGFloat = 0
        for i in 0..<span.columns {
            w += columnWidth(column + i)
        }
        return w + gap * CGFloat(span.columns - 1)
    }

    /// The pixel height a `GridSpan` occupies.
    func height(of span: GridSpan) -> CGFloat {
        rowHeight * CGFloat(span.rows) + gap * CGFloat(max(0, span.rows - 1))
    }

    /// The pixel size a `GridSpan` occupies, assuming it starts in column 0.
    /// (Kept for callers that don't track the origin column; prefer
    /// `frame(origin:span:)`.)
    func size(of span: GridSpan) -> CGSize {
        CGSize(width: width(of: span, startingAt: 0), height: height(of: span))
    }

    /// The pixel rect (in the canvas's top-left coordinate space) for a widget
    /// at `origin` with `span`.
    func frame(origin: GridPoint, span: GridSpan) -> CGRect {
        CGRect(
            origin: CGPoint(
                x: columnX(origin.column),
                y: step.height * CGFloat(origin.row)
            ),
            size: CGSize(
                width: width(of: span, startingAt: origin.column),
                height: height(of: span)
            )
        )
    }

    /// Snap a proposed pixel top-left to the nearest grid cell, then **clamp so
    /// the `span` stays entirely inside the grid**. The returned origin is always
    /// in bounds for that span (a move can never leave the grid — overlap is the
    /// store's job to reject).
    func snappedOrigin(pixelTopLeft point: CGPoint, span: GridSpan) -> GridPoint {
        let maxColumn = max(0, grid.columns - span.columns)
        let maxRow = max(0, grid.rows - span.rows)

        // Nearest column by its left edge. On an exact tie the later (further
        // right) column wins, matching a round-half-up on the old uniform grid.
        var bestColumn = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for c in 0...maxColumn {
            let d = abs(columnX(c) - point.x)
            if d <= bestDistance {
                bestDistance = d
                bestColumn = c
            }
        }

        let rawRow = step.height > 0 ? Int((point.y / step.height).rounded()) : 0

        return GridPoint(
            column: min(max(0, bestColumn), maxColumn),
            row: min(max(0, rawRow), maxRow)
        )
    }

    /// The snapped grid origin a widget currently at `origin` would land on after
    /// a drag of `translation`.
    ///
    /// `translation` is added **once** to the widget's committed top-left — it is
    /// a pure delta from a fixed reference, never fed back into the measurement.
    func proposedOrigin(movingFrom origin: GridPoint, span: GridSpan, by translation: CGSize) -> GridPoint {
        let base = frame(origin: origin, span: span).origin
        let moved = CGPoint(x: base.x + translation.width, y: base.y + translation.height)
        return snappedOrigin(pixelTopLeft: moved, span: span)
    }
}

/// Maps a resize drag onto the feature's ordered list of supported widget sizes.
/// Pure — no pixels leak into the layout; the drag just steps an index.
nonisolated enum DashboardResizeStepper {

    /// The size a resize drag of `translation` from `current` lands on, given the
    /// feature's `supported` sizes (already filtered + ordered small→large).
    /// `stepDistance` is drag sensitivity, not a widget dimension.
    static func targetSize(
        current: ComponentSize,
        supported: [ComponentSize],
        translation: CGSize,
        stepDistance: CGFloat
    ) -> ComponentSize {
        guard
            stepDistance > 0,
            let start = supported.firstIndex(of: current)
        else { return current }

        // Growing = dragging the bottom-trailing handle down and/or right.
        let travel = (translation.width + translation.height) / 2
        let steps = Int((travel / stepDistance).rounded())
        let target = min(max(0, start + steps), supported.count - 1)
        return supported[target]
    }
}
