//
//  HomeInteractionTests.swift
//  DashTests
//
//  M5.3.0/M5.3.1 — the Home launcher's behaviour: an app icon forwards its
//  `featureID` (never `ShellStore`); `HomeSpaceView` renders exactly its page;
//  the Dashboard and the Home pages are ONE horizontal sequence of spaces
//  (`SpacePagerView` / `ShellSurface.spaceIndex`); and closing a feature returns
//  to the exact Home page it was opened from.
//

import Foundation
import SwiftUI
import Testing
@testable import Dash

// MARK: - The tile forwards the right id

@MainActor
@Suite("HomeAppTile tap")
struct HomeTileTapTests {

    @Test("tapping a tile requests its own feature id")
    func requestsFeatureID() {
        var requested: [FeatureID] = []
        HomeAppTile(manifest: nil, featureID: "maps", onOpen: { requested.append($0) }).activate()
        #expect(requested == ["maps"])
    }

    @Test("different tiles request different feature ids")
    func distinctFeatureIDs() {
        var requested: [FeatureID] = []
        let sink: (FeatureID) -> Void = { requested.append($0) }

        HomeAppTile(manifest: nil, featureID: "maps", onOpen: sink).activate()
        HomeAppTile(manifest: nil, featureID: "speedometer", onOpen: sink).activate()

        #expect(requested == ["maps", "speedometer"])
    }

    @Test("the tile is feature-agnostic — it forwards any id, resolved or not")
    func featureAgnostic() {
        var requested: [FeatureID] = []
        // No manifest (feature not registered) — still just forwards the id.
        HomeAppTile(manifest: nil, featureID: "future-app", onOpen: { requested.append($0) }).activate()
        #expect(requested == ["future-app"])
    }
}

// MARK: - HomeSpaceView renders its page + forwards

@MainActor
@Suite("HomeSpaceView")
struct HomeSpaceViewTests {

    private func view(
        _ featureIDs: [FeatureID],
        registry: FeatureRegistry? = nil,
        onOpen: @escaping (FeatureID) -> Void = { _ in }
    ) -> HomeSpaceView {
        HomeSpaceView(
            page: HomePage(apps: featureIDs.map { HomeAppPlacement(featureID: $0) }),
            registry: registry ?? FeatureRegistry.makeDefault(),
            onOpenFeature: onOpen
        )
    }

    @Test("the default (registry-derived) layout puts the registered feature on Home page 0")
    func resolvesRegisteredFeatures() {
        let registry = FeatureRegistry.makeDefault()
        let layout = HomeLayout.paginate(featureIDs: registry.manifests.map(\.id))
        let firstPageIDs = layout.page(at: 0)?.apps.map(\.featureID) ?? []

        let home = view(firstPageIDs, registry: registry)

        #expect(home.featureIDs.contains(MapFeature.id))
        // …and the id resolves to a real manifest for the tile.
        #expect(registry.feature(MapFeature.id)?.manifest.title == "Google Maps")
    }

    @Test("featureIDs are exactly the page's apps, in slot order")
    func featureIDsMatchPage() {
        #expect(view(["a", "b", "c"]).featureIDs == ["a", "b", "c"])
        #expect(view([]).featureIDs.isEmpty)
    }
}

// MARK: - Open → close returns to the same Home page

@MainActor
@Suite("Home app → full-screen navigation")
struct HomeNavigationTests {

    /// Mirrors what `DashboardShell` wires: `onOpenFeature` → `ShellStore.openApp`.
    private func tapTile(_ shell: ShellStore, _ id: FeatureID) {
        shell.openApp(id)
    }

    @Test("opening an app from Home page N returns to Home page N")
    func returnsToHomePage() {
        for page in [0, 1, 2, 4] {
            let shell = ShellStore()
            shell.showHome(page: page)

            tapTile(shell, "maps")
            #expect(shell.surface == .app("maps"))
            #expect(shell.returnSurface == .home(page: page))

            shell.closeApp()
            #expect(shell.surface == .home(page: page))
        }
    }

    @Test("opening an app from Home, then a different app, still returns to Home")
    func multipleApps() {
        let shell = ShellStore()
        shell.showHome(page: 2)

        tapTile(shell, "maps")
        #expect(shell.surface == .app("maps"))
        shell.closeApp()

        tapTile(shell, "music")
        #expect(shell.surface == .app("music"))
        shell.closeApp()

        #expect(shell.surface == .home(page: 2))
    }

    @Test("opening from the Dashboard still returns to the Dashboard (unchanged)")
    func dashboardUnaffected() {
        let shell = ShellStore()
        shell.showDashboard()
        shell.openApp("maps")
        shell.closeApp()
        #expect(shell.surface == .dashboard)
    }
}

// MARK: - Shell-level horizontal space navigation

@MainActor
@Suite("Horizontal space navigation")
struct HomePagingShellTests {

    /// `SpacePagerView` for a given surface + Home layout, so we can read its
    /// seeded space index and the pure surface mapping.
    private func pager(
        surface: ShellSurface,
        homeApps: [FeatureID],
        capacity: Int = HomeGrid.capacity
    ) -> SpacePagerView {
        SpacePagerView(
            shell: ShellStore(surface: surface),
            homeLayout: HomeLayoutStore(
                seed: .paginate(featureIDs: homeApps, capacity: capacity),
                defaults: UserDefaults(suiteName: "pager-h-\(UUID().uuidString)")!
            ),
            dashboards: DashboardCollectionStore(
                seed: .starter(featureID: "maps"),
                defaults: UserDefaults(suiteName: "pager-d-\(UUID().uuidString)")!
            ),
            dashboardEdit: DashboardEditModel(),
            registry: FeatureRegistry.makeDefault(),
            grid: .standard
        )
    }

    private func manyIDs(_ n: Int) -> [FeatureID] { (0..<n).map { "app-\($0)" } }

    @Test("the pager seeds its space index from the shell surface")
    func seedsFromShell() {
        #expect(pager(surface: .dashboard, homeApps: ["maps"]).currentSpaceIndex == 0)
        #expect(pager(surface: .home(page: 0), homeApps: ["maps"]).currentSpaceIndex == 1)
    }

    @Test("initial layout: only Dashboard ←→ Home page 0")
    func initialSpaces() {
        let dash = pager(surface: .dashboard, homeApps: ["maps"])
        #expect(dash.surfaceForCurrentSpace == .dashboard)
        #expect(dash.currentHomePage == nil)

        let home = pager(surface: .home(page: 0), homeApps: ["maps"])
        #expect(home.surfaceForCurrentSpace == .home(page: 0))
        #expect(home.currentHomePage == 0)
    }

    @Test("with a second Home page, Home page 1 is the space after Home page 0")
    func secondHomePage() {
        let ids = manyIDs(HomeGrid.capacity + 1) // spills onto a second page
        let p = pager(surface: .home(page: 1), homeApps: ids)
        #expect(p.currentSpaceIndex == 2)
        #expect(p.surfaceForCurrentSpace == .home(page: 1))
        #expect(p.currentHomePage == 1)
    }

    /// The `DashboardShell` wiring: a dot / sidebar selection → `ShellStore.goToPage`.
    @Test("a Home page selection updates the Home surface page")
    func pageSelectionUpdatesSurface() {
        let shell = ShellStore()
        shell.showHome(page: 0)

        shell.goToPage(2)
        #expect(shell.surface == .home(page: 2))

        // …and opening / closing an app from there keeps that page.
        shell.openApp("maps")
        shell.closeApp()
        #expect(shell.surface == .home(page: 2))
    }

    @Test("goToPage on the Dashboard is a no-op (there is one Dashboard)")
    func dashboardPagingUnaffected() {
        let shell = ShellStore()
        shell.showDashboard()
        shell.goToPage(1)
        #expect(shell.surface == .dashboard)
    }

    @Test("stepping between adjacent spaces, and the bounds at each end")
    func adjacentStepsAndBounds() {
        // One Home page: Dashboard (0) ←→ Home page 0 (1).
        #expect(ShellSurface.forSpaceIndex(0 - 1, homePageCount: 1) == .dashboard)     // before first
        #expect(ShellSurface.forSpaceIndex(0 + 1, homePageCount: 1) == .home(page: 0)) // Dashboard → Home
        #expect(ShellSurface.forSpaceIndex(1 - 1, homePageCount: 1) == .dashboard)     // Home → Dashboard
        #expect(ShellSurface.forSpaceIndex(1 + 1, homePageCount: 1) == .home(page: 0)) // past last → clamp

        // Two Home pages: Dashboard (0), Home 0 (1), Home 1 (2).
        #expect(ShellSurface.forSpaceIndex(1 + 1, homePageCount: 2) == .home(page: 1))
        #expect(ShellSurface.forSpaceIndex(2 - 1, homePageCount: 2) == .home(page: 0))
        #expect(ShellSurface.forSpaceIndex(2 + 1, homePageCount: 2) == .home(page: 1)) // past last → clamp
    }
}
