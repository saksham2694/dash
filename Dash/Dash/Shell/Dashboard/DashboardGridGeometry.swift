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
//  Also here: `DashboardResizeStepper`, the pure "which supported size does this
//  resize drag land on" helper — so interactive resize snaps through the
//  existing `ComponentSize` footprints, never arbitrary pixel dimensions.
//

import CoreGraphics

nonisolated struct DashboardGridGeometry: Equatable, Sendable {

    let grid: DashboardGrid
    let canvas: CGSize
    let gap: CGFloat

    init(grid: DashboardGrid, canvas: CGSize, gap: CGFloat) {
        self.grid = grid
        self.canvas = canvas
        self.gap = gap
    }

    /// One cell's pixel size on this canvas.
    var cell: CGSize {
        guard grid.columns > 0, grid.rows > 0 else { return .zero }
        let w = (canvas.width - gap * CGFloat(grid.columns - 1)) / CGFloat(grid.columns)
        let h = (canvas.height - gap * CGFloat(grid.rows - 1)) / CGFloat(grid.rows)
        return CGSize(width: max(0, w), height: max(0, h))
    }

    /// The distance from one cell's top-left to the next (cell + gap).
    var step: CGSize {
        CGSize(width: cell.width + gap, height: cell.height + gap)
    }

    /// The pixel size a `GridSpan` occupies (spanned cells + interior gaps).
    func size(of span: GridSpan) -> CGSize {
        CGSize(
            width: cell.width * CGFloat(span.columns) + gap * CGFloat(max(0, span.columns - 1)),
            height: cell.height * CGFloat(span.rows) + gap * CGFloat(max(0, span.rows - 1))
        )
    }

    /// The pixel rect (in the canvas's top-left coordinate space) for a widget
    /// at `origin` with `span`.
    func frame(origin: GridPoint, span: GridSpan) -> CGRect {
        CGRect(
            origin: CGPoint(
                x: step.width * CGFloat(origin.column),
                y: step.height * CGFloat(origin.row)
            ),
            size: size(of: span)
        )
    }

    /// Snap a proposed pixel top-left to the nearest grid cell, then **clamp so
    /// the `span` stays entirely inside the grid**. The returned origin is always
    /// in bounds for that span (a move can never leave the grid — overlap is the
    /// store's job to reject).
    func snappedOrigin(pixelTopLeft point: CGPoint, span: GridSpan) -> GridPoint {
        let rawColumn = step.width > 0 ? Int((point.x / step.width).rounded()) : 0
        let rawRow = step.height > 0 ? Int((point.y / step.height).rounded()) : 0

        let maxColumn = max(0, grid.columns - span.columns)
        let maxRow = max(0, grid.rows - span.rows)

        return GridPoint(
            column: min(max(0, rawColumn), maxColumn),
            row: min(max(0, rawRow), maxRow)
        )
    }

    /// The snapped grid origin a widget currently at `origin` would land on after
    /// a drag of `translation`.
    ///
    /// `translation` is added **once** to the widget's committed top-left — it is
    /// a pure delta from a fixed reference, never fed back into the measurement.
    /// (Feeding the live `.offset` back into a `.local` drag translation is what
    /// makes a SwiftUI drag oscillate; keeping this a one-shot delta is the fix.)
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
