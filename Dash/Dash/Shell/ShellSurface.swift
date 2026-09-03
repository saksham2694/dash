//
//  ShellSurface.swift
//  Dash
//
//  What the CarPlay-style shell is showing right now: the (single) Dashboard,
//  an App-Home page, or one feature full-screen. Pure value type — no view code,
//  no feature logic.
//
//  Horizontal navigation model (M5.3.1): Dashboard and the Home pages form ONE
//  left-to-right sequence of "spaces" —
//
//      Dashboard ←→ Home page 0 ←→ Home page 1 ←→ …
//
//  There is exactly one Dashboard (no dashboard pages). `spaceIndex` /
//  `forSpaceIndex` flatten `ShellSurface` ↔ that sequence for the shell's swipe
//  pager. `.app` is not part of the sequence — it is shown instead of the pager.
//
//  `Codable` so a later milestone could persist the last surface; nothing
//  persists it today.
//

import Foundation

nonisolated enum ShellSurface: Equatable, Sendable, Codable {

    /// The widget dashboard. One space — no pages.
    case dashboard

    /// The app launcher, on the given (0-based) page.
    case home(page: Int)

    /// One feature shown full-screen.
    case app(FeatureID)

    /// Where the shell starts / returns when nothing else is chosen.
    static var defaultSurface: ShellSurface { .home(page: 0) }

    /// Whether a feature is full-screen.
    var isApp: Bool {
        if case .app = self { return true }
        return false
    }

    /// The Home page index, or `nil` for the Dashboard / a full-screen app.
    var homePage: Int? {
        if case .home(let page) = self { return page }
        return nil
    }
}

// MARK: - Horizontal spaces

extension ShellSurface {

    /// Total spaces in the horizontal sequence: the Dashboard plus every Home
    /// page (Home always has at least one page).
    static func spaceCount(homePageCount: Int) -> Int {
        1 + max(1, homePageCount)
    }

    /// This surface's index in the horizontal sequence — `0` = Dashboard,
    /// `1…` = Home page `0…`. `nil` for `.app` (the pager isn't shown then).
    /// A Home page index beyond the last is clamped.
    func spaceIndex(homePageCount: Int) -> Int? {
        switch self {
        case .dashboard:
            return 0
        case .home(let page):
            let lastHomePage = max(0, homePageCount - 1)
            return min(max(0, page), lastHomePage) + 1
        case .app:
            return nil
        }
    }

    /// The surface for a horizontal-sequence index (see `spaceIndex`). Out-of-
    /// range indices clamp to the Dashboard / the last Home page.
    static func forSpaceIndex(_ index: Int, homePageCount: Int) -> ShellSurface {
        if index <= 0 { return .dashboard }
        let lastHomePage = max(0, homePageCount - 1)
        return .home(page: min(index - 1, lastHomePage))
    }
}
