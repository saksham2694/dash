//
//  DashboardGrid.swift
//  Dash
//
//  The fixed cell grid a dashboard page is laid out on, plus the mapping from a
//  `ComponentSize` to the number of cells it occupies.
//
//  This is a **shell** concern (M5 proposal §4, §7): the model stores only a
//  size + origin per widget; the shell decides the footprint. SDK-neutral — cell
//  counts, never points or SwiftUI types — so it is trivially unit-testable.
//

import Foundation

/// A widget's top-left cell on the grid (0-based).
nonisolated struct GridPoint: Equatable, Hashable, Sendable, Codable {
    var column: Int
    var row: Int

    init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

/// How many cells wide / tall a widget is.
nonisolated struct GridSpan: Equatable, Hashable, Sendable, Codable {
    var columns: Int
    var rows: Int

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

/// A widget's occupied cell region — a half-open rectangle
/// `[minColumn, maxColumn) × [minRow, maxRow)`.
nonisolated struct GridRect: Equatable, Sendable {
    var origin: GridPoint
    var span: GridSpan

    var minColumn: Int { origin.column }
    var minRow: Int { origin.row }
    var maxColumn: Int { origin.column + span.columns }
    var maxRow: Int { origin.row + span.rows }

    /// Whether two cell regions share at least one cell.
    func intersects(_ other: GridRect) -> Bool {
        minColumn < other.maxColumn && maxColumn > other.minColumn &&
        minRow < other.maxRow && maxRow > other.minRow
    }
}

/// The dashboard's fixed grid. One instance (`.standard`) is used app-wide;
/// changing the dashboard's dimensions is a one-line change here.
nonisolated struct DashboardGrid: Equatable, Sendable {

    var columns: Int
    var rows: Int

    /// Landscape-iPad friendly. The single grid Dash ships with.
    static let standard = DashboardGrid(columns: 6, rows: 4)

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    /// Cells a widget of `size` occupies. `.full` is not a dashboard widget — it
    /// maps to the whole grid so any layout that places it is caught by
    /// validation (`DashboardLayoutValidator` also rejects it outright).
    func span(for size: ComponentSize) -> GridSpan {
        switch size {
        case .compact: return GridSpan(columns: 2, rows: 1)
        case .medium:  return GridSpan(columns: 3, rows: 2)
        case .large:   return GridSpan(columns: columns, rows: 2)
        case .full:    return GridSpan(columns: columns, rows: rows)
        }
    }

    /// The cell region a placement occupies on this grid.
    func rect(for placement: WidgetPlacement) -> GridRect {
        GridRect(origin: placement.origin, span: span(for: placement.size))
    }

    /// Whether a cell region fits entirely inside the grid.
    func contains(_ rect: GridRect) -> Bool {
        rect.minColumn >= 0 && rect.minRow >= 0 &&
        rect.maxColumn <= columns && rect.maxRow <= rows
    }
}
