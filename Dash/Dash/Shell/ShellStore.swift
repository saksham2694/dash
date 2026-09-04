//
//  ShellStore.swift
//  Dash
//
//  Navigation state for the CarPlay-style shell: which `ShellSurface` is
//  showing, and where to return after a full-screen app closes.
//
//  Deliberately pure and feature-agnostic:
//    • No feature-specific logic — `openApp` takes an opaque `FeatureID` and
//      never validates it against the registry (the shell view does that).
//    • No SDK types, no networking, no layout.
//    • `@MainActor` because SwiftUI observes it on the main actor.
//
//  M5.3.1: there is one Dashboard (no dashboard pages). `goToPage` only affects
//  the Home space. Horizontal swiping between Dashboard and Home pages is driven
//  by the shell's pager calling `showDashboard()` / `showHome(page:)`.
//
//  M5.5.2a: the sidebar is a fixed, always-visible rail — there is no
//  collapse/expand state.
//

import Combine
import Foundation

@MainActor
final class ShellStore: ObservableObject {

    /// What the shell is currently showing.
    @Published private(set) var surface: ShellSurface

    /// The last non-`.app` surface — where `closeApp()` returns. Never an
    /// `.app` surface.
    private(set) var returnSurface: ShellSurface

    init(surface: ShellSurface = .defaultSurface) {
        self.surface = surface
        self.returnSurface = surface.isApp ? .defaultSurface : surface
    }

    // MARK: - Spaces

    /// Show the widget dashboard (the single Dashboard space).
    func showDashboard() {
        goToSpace(.dashboard)
    }

    /// Show the App-Home launcher on `page`.
    func showHome(page: Int = 0) {
        goToSpace(.home(page: page))
    }

    /// Change the Home page. No-op on the Dashboard (one page) or while a
    /// full-screen app is open.
    func goToPage(_ page: Int) {
        if case .home = surface { showHome(page: page) }
    }

    // MARK: - Full-screen apps

    /// Open a feature full-screen. Remembers the current space so `closeApp()`
    /// can return to it; switching directly between apps keeps that memory.
    func openApp(_ id: FeatureID) {
        if !surface.isApp { returnSurface = surface }
        surface = .app(id)
    }

    /// Leave the full-screen app, returning to the space it was opened from.
    /// No-op when no app is open.
    func closeApp() {
        guard surface.isApp else { return }
        surface = returnSurface
    }

    /// The Home/Dashboard toggle in the rail: from the Dashboard → Home; from a
    /// Home page (or a full-screen app) → the Dashboard.
    func toggleHomeDashboard() {
        switch surface {
        case .dashboard:
            showHome()
        case .home, .app:
            showDashboard()
        }
    }

    // MARK: - Private

    private func goToSpace(_ newSurface: ShellSurface) {
        returnSurface = newSurface
        surface = newSurface
    }
}
