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
        #expect(!ShellSurface.dashboard.isApp)
    }

    @Test("homePage is the Home page index, and nil for the Dashboard / an app")
    func homePage() {
        #expect(ShellSurface.home(page: 2).homePage == 2)
        #expect(ShellSurface.dashboard.homePage == nil)
        #expect(ShellSurface.app("maps").homePage == nil)
    }

    @Test("round-trips through Codable")
    func codable() throws {
        let surfaces: [ShellSurface] = [.home(page: 0), .dashboard, .app("maps")]
        for surface in surfaces {
            let data = try JSONEncoder().encode(surface)
            #expect(try JSONDecoder().decode(ShellSurface.self, from: data) == surface)
        }
    }
}

@Suite("ShellSurface horizontal spaces")
struct ShellSpacesTests {

    @Test("space count is the Dashboard plus every Home page (Home has ≥ 1)")
    func spaceCount() {
        #expect(ShellSurface.spaceCount(homePageCount: 1) == 2)
        #expect(ShellSurface.spaceCount(homePageCount: 2) == 3)
        #expect(ShellSurface.spaceCount(homePageCount: 3) == 4)
        #expect(ShellSurface.spaceCount(homePageCount: 0) == 2)
    }

    @Test("Dashboard is space 0; Home page N is space N + 1; an app has no space")
    func spaceIndex() {
        #expect(ShellSurface.dashboard.spaceIndex(homePageCount: 3) == 0)
        #expect(ShellSurface.home(page: 0).spaceIndex(homePageCount: 3) == 1)
        #expect(ShellSurface.home(page: 2).spaceIndex(homePageCount: 3) == 3)
        #expect(ShellSurface.app("maps").spaceIndex(homePageCount: 3) == nil)
    }

    @Test("a Home page index beyond what exists is clamped")
    func spaceIndexClamps() {
        #expect(ShellSurface.home(page: 9).spaceIndex(homePageCount: 2) == 2)
        #expect(ShellSurface.home(page: -4).spaceIndex(homePageCount: 2) == 1)
    }

    @Test("forSpaceIndex is the inverse mapping, clamped at both ends")
    func forSpaceIndex() {
        #expect(ShellSurface.forSpaceIndex(0, homePageCount: 3) == .dashboard)
        #expect(ShellSurface.forSpaceIndex(1, homePageCount: 3) == .home(page: 0))
        #expect(ShellSurface.forSpaceIndex(3, homePageCount: 3) == .home(page: 2))
        #expect(ShellSurface.forSpaceIndex(-2, homePageCount: 3) == .dashboard)
        #expect(ShellSurface.forSpaceIndex(99, homePageCount: 3) == .home(page: 2))
    }

    @Test("adjacent-space steps: Dashboard ←→ Home page 0 ←→ Home page 1")
    func adjacentSteps() {
        // Initially only Dashboard ←→ Home page 0.
        #expect(ShellSurface.forSpaceIndex(1, homePageCount: 1) == .home(page: 0)) // Dashboard → right
        #expect(ShellSurface.forSpaceIndex(0, homePageCount: 1) == .dashboard)      // Home page 0 → left

        // With two Home pages: Dashboard, Home 0, Home 1.
        #expect(ShellSurface.forSpaceIndex(2, homePageCount: 2) == .home(page: 1))  // Home 0 → right
        #expect(ShellSurface.forSpaceIndex(1, homePageCount: 2) == .home(page: 0))  // Home 1 → left

        // Bounds: cannot step before the Dashboard or past the last Home page.
        #expect(ShellSurface.forSpaceIndex(-1, homePageCount: 2) == .dashboard)
        #expect(ShellSurface.forSpaceIndex(3, homePageCount: 2) == .home(page: 1))
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
        #expect(store.surface == .dashboard)

        store.showHome(page: 1)
        #expect(store.surface == .home(page: 1))
    }

    @Test("openApp then closeApp returns to the space it was opened from")
    func openThenClose() {
        let store = ShellStore()
        store.showHome(page: 2)

        store.openApp("maps")
        #expect(store.surface == .app("maps"))

        store.closeApp()
        #expect(store.surface == .home(page: 2))
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
        store.showDashboard()

        store.openApp("maps")
        store.openApp("music")
        #expect(store.surface == .app("music"))

        store.closeApp()
        #expect(store.surface == .dashboard)
    }

    @Test("closeApp is a no-op when no app is open")
    func closeWithoutApp() {
        let store = ShellStore()
        store.showDashboard()

        store.closeApp()
        #expect(store.surface == .dashboard)
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

    @Test("goToPage changes the Home page only")
    func goToPage() {
        let store = ShellStore()

        store.goToPage(3)
        #expect(store.surface == .home(page: 3))

        store.showDashboard()
        store.goToPage(1)
        #expect(store.surface == .dashboard) // no-op: there is one Dashboard

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
