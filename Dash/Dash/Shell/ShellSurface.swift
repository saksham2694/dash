//
//  ShellSurface.swift
//  Dash
//
//  What the CarPlay-style shell is showing right now: an App-Home page, a
//  Dashboard page, or one feature full-screen. Pure value type — no view code,
//  no feature logic (M5 proposal §2).
//
//  `Codable` so a later milestone can persist and restore the last surface;
//  M5.0 does not persist anything.
//

import Foundation

nonisolated enum ShellSurface: Equatable, Sendable, Codable {

    /// The app launcher (grid of feature tiles), on the given page.
    case home(page: Int)

    /// The customizable widget dashboard, on the given page.
    case dashboard(page: Int)

    /// One feature shown full-screen.
    case app(FeatureID)

    /// Where the shell starts / returns when nothing else is chosen.
    static var defaultSurface: ShellSurface { .home(page: 0) }

    /// Whether a feature is full-screen.
    var isApp: Bool {
        if case .app = self { return true }
        return false
    }

    /// The page index for a space surface; `nil` for `.app`.
    var page: Int? {
        switch self {
        case .home(let page), .dashboard(let page): return page
        case .app: return nil
        }
    }
}
