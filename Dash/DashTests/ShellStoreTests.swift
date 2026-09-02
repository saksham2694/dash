//
//  ShellStoreTests.swift
//  DashTests
//
//  The pure navigation/chrome state for the CarPlay-style shell (M5.0):
//  `ShellSurface` and `ShellStore`. No SwiftUI, no features, no SDK.
//

import Foundation
import Testing
@testable import Dash

@Suite("ShellSurface")
struct ShellSurfaceTests {

    @Test("the default surface is Home, page 0")
    func defaultSurface() {
        #expect(ShellSurface.defaultSurface == .home(page: 0))
    }

    @Test("isApp is true only for the app case")
    func isApp() {
        #expect(ShellSurface.app("maps").isApp)
        #expect(!ShellSurface.home(page: 0).isApp)
        #expect(!ShellSurface.dashboard(page: 1).isApp)
    }

    @Test("page is the space page, and nil for a full-screen app")
    func page() {
        #expect(ShellSurface.home(page: 2).page == 2)
        #expect(ShellSurface.dashboard(page: 3).page == 3)
        #expect(ShellSurface.app("maps").page == nil)
    }

    @Test("round-trips through Codable")
    func codable() throws {
        let surfaces: [ShellSurface] = [.home(page: 0), .dashboard(page: 2), .app("maps")]
        for surface in surfaces {
            let data = try JSONEncoder().encode(surface)
            #expect(try JSONDecoder().decode(ShellSurface.self, from: data) == surface)
        }
    }
}

@MainActor
@Suite("ShellStore")
struct ShellStoreTests {

    @Test("starts on the default surface with the sidebar expanded")
    func initialState() {
        let store = ShellStore()
        #expect(store.surface == .home(page: 0))
        #expect(store.sidebarCollapsed == false)
    }

    @Test("showHome / showDashboard switch spaces and page")
    func switchSpaces() {
        let store = ShellStore()

        store.showDashboard()
        #expect(store.surface == .dashboard(page: 0))

        store.showHome(page: 1)
        #expect(store.surface == .home(page: 1))
    }

    @Test("openApp then closeApp returns to the space it was opened from")
    func openThenClose() {
        let store = ShellStore()
        store.showDashboard(page: 2)

        store.openApp("maps")
        #expect(store.surface == .app("maps"))

        store.closeApp()
        #expect(store.surface == .dashboard(page: 2))
    }

    @Test("openApp from Home returns to Home on close")
    func openFromHome() {
        let store = ShellStore()

        store.openApp("maps")
        store.closeApp()

        #expect(store.surface == .home(page: 0))
    }

    @Test("switching directly between apps keeps the original return surface")
    func switchApps() {
        let store = ShellStore()
        store.showDashboard(page: 1)

        store.openApp("maps")
        store.openApp("music")
        #expect(store.surface == .app("music"))

        store.closeApp()
        #expect(store.surface == .dashboard(page: 1))
    }

    @Test("closeApp is a no-op when no app is open")
    func closeWithoutApp() {
        let store = ShellStore()
        store.showDashboard(page: 1)

        store.closeApp()
        #expect(store.surface == .dashboard(page: 1))
    }

    @Test("navigating to a space while an app is open also leaves the app")
    func spaceWhileInApp() {
        let store = ShellStore()
        store.openApp("maps")

        store.showHome()
        #expect(store.surface == .home(page: 0))

        // And a subsequent closeApp does nothing (already left).
        store.closeApp()
        #expect(store.surface == .home(page: 0))
    }

    @Test("goToPage changes the page within the current space only")
    func goToPage() {
        let store = ShellStore()

        store.goToPage(3)
        #expect(store.surface == .home(page: 3))

        store.showDashboard()
        store.goToPage(1)
        #expect(store.surface == .dashboard(page: 1))

        store.openApp("maps")
        store.goToPage(5)
        #expect(store.surface == .app("maps")) // no-op while a full-screen app is open
    }

    @Test("toggleSidebar flips the collapsed flag")
    func toggleSidebar() {
        let store = ShellStore()

        store.toggleSidebar()
        #expect(store.sidebarCollapsed)

        store.toggleSidebar()
        #expect(!store.sidebarCollapsed)
    }

    @Test("a store created on an app surface still returns somewhere sane")
    func initialisedOnApp() {
        let store = ShellStore(surface: .app("maps"))
        #expect(store.surface == .app("maps"))

        store.closeApp()
        #expect(store.surface == .home(page: 0))
    }
}
