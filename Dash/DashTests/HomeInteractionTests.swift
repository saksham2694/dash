//
//  HomeInteractionTests.swift
//  DashTests
//
//  M5.3.0 — tapping a Home app tile opens its feature full-screen, and closing
//  returns to the exact Home page it was opened from. The tile only forwards
//  `HomeAppPlacement.featureID`; the surface bookkeeping is the existing
//  `ShellStore` behaviour (unchanged).
//

import Foundation
import SwiftUI
import Testing
@testable import Dash

// MARK: - The tile forwards the right id

@MainActor
@Suite("HomeAppTileButton tap")
struct HomeTileTapTests {

    @Test("tapping a tile requests its own feature id")
    func requestsFeatureID() {
        var requested: [FeatureID] = []
        HomeAppTileButton(manifest: nil, featureID: "maps", onOpen: { requested.append($0) }).activate()
        #expect(requested == ["maps"])
    }

    @Test("different tiles request different feature ids")
    func distinctFeatureIDs() {
        var requested: [FeatureID] = []
        let sink: (FeatureID) -> Void = { requested.append($0) }

        HomeAppTileButton(manifest: nil, featureID: "maps", onOpen: sink).activate()
        HomeAppTileButton(manifest: nil, featureID: "speedometer", onOpen: sink).activate()

        #expect(requested == ["maps", "speedometer"])
    }

    @Test("the tile is feature-agnostic — it forwards any id, resolved or not")
    func featureAgnostic() {
        var requested: [FeatureID] = []
        // No manifest (feature not registered) — still just forwards the id.
        HomeAppTileButton(manifest: nil, featureID: "future-app", onOpen: { requested.append($0) }).activate()
        #expect(requested == ["future-app"])
    }
}

// MARK: - HomeSpaceView resolves + forwards

@MainActor
@Suite("HomeSpaceView")
struct HomeSpaceViewTests {

    private func view(
        _ layout: HomeLayout,
        registry: FeatureRegistry? = nil,
        page: Int = 0,
        onOpen: @escaping (FeatureID) -> Void = { _ in }
    ) -> HomeSpaceView {
        let store = HomeLayoutStore(
            seed: layout,
            defaults: UserDefaults(suiteName: "home-space-\(UUID().uuidString)")!
        )
        return HomeSpaceView(
            layoutStore: store, registry: registry ?? FeatureRegistry.makeDefault(),
            requestedPage: page, onSelectPage: { _ in }, onOpenFeature: onOpen
        )
    }

    @Test("the default (registry-derived) layout puts the registered feature on Home")
    func resolvesRegisteredFeatures() {
        let registry = FeatureRegistry.makeDefault()
        let layout = HomeLayout.starter(featureIDs: registry.manifests.map(\.id))

        let home = view(layout, registry: registry)

        #expect(home.currentPageFeatureIDs.contains(MapFeature.id))
        // …and the id resolves to a real manifest for the tile.
        #expect(registry.feature(MapFeature.id)?.manifest.title == "Maps")
    }

    @Test("clamps the requested page to the pages that exist")
    func clampsPage() {
        let layout = HomeLayout.starter(featureIDs: ["a", "b", "c"], appsPerPage: 1) // 3 pages

        #expect(view(layout, page: -3).resolvedPageIndex == 0)
        #expect(view(layout, page: 0).resolvedPageIndex == 0)
        #expect(view(layout, page: 2).resolvedPageIndex == 2)
        #expect(view(layout, page: 99).resolvedPageIndex == 2)
    }

    @Test("shows only the current page's apps")
    func currentPageOnly() {
        let layout = HomeLayout.starter(featureIDs: ["a", "b", "c", "d"], appsPerPage: 2)

        #expect(view(layout, page: 0).currentPageFeatureIDs == ["a", "b"])
        #expect(view(layout, page: 1).currentPageFeatureIDs == ["c", "d"])
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

    @Test("opening from Dashboard still returns to Dashboard (unchanged)")
    func dashboardUnaffected() {
        let shell = ShellStore()
        shell.showDashboard(page: 1)
        shell.openApp("maps")
        shell.closeApp()
        #expect(shell.surface == .dashboard(page: 1))
    }
}
