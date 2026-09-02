//
//  ShellStore.swift
//  Dash
//
//  Navigation + chrome state for the CarPlay-style shell: which `ShellSurface`
//  is showing, whether the sidebar is collapsed, and where to return after a
//  full-screen app closes.
//
//  Deliberately pure and feature-agnostic (M5 proposal §2, §9):
//    • No feature-specific logic — `openApp` takes an opaque `FeatureID` and
//      never validates it against the registry (the shell view does that).
//    • No SDK types, no networking, no layout.
//    • `@MainActor` because SwiftUI observes it on the main actor.
//

import Combine
import Foundation

@MainActor
final class ShellStore: ObservableObject {

    /// What the shell is currently showing.
    @Published private(set) var surface: ShellSurface

    /// Whether the sidebar is in its narrow, icon-only state.
    @Published private(set) var sidebarCollapsed: Bool

    /// The last non-`.app` surface — where `closeApp()` returns. Never an
    /// `.app` surface.
    private(set) var returnSurface: ShellSurface

    init(surface: ShellSurface = .defaultSurface, sidebarCollapsed: Bool = false) {
        self.surface = surface
        self.sidebarCollapsed = sidebarCollapsed
        self.returnSurface = surface.isApp ? .defaultSurface : surface
    }

    // MARK: - Spaces

    /// Show the App-Home launcher.
    func showHome(page: Int = 0) {
        goToSpace(.home(page: page))
    }

    /// Show the widget dashboard.
    func showDashboard(page: Int = 0) {
        goToSpace(.dashboard(page: page))
    }

    /// Change the page within the current space. No-op while a full-screen app
    /// is open.
    func goToPage(_ page: Int) {
        switch surface {
        case .home: showHome(page: page)
        case .dashboard: showDashboard(page: page)
        case .app: break
        }
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

    // MARK: - Sidebar

    func toggleSidebar() {
        sidebarCollapsed.toggle()
    }

    // MARK: - Private

    private func goToSpace(_ newSurface: ShellSurface) {
        returnSurface = newSurface
        surface = newSurface
    }
}
