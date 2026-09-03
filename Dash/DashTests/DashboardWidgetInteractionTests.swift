//
//  DashboardWidgetInteractionTests.swift
//  DashTests
//
//  M5.3.0 — tapping a Dashboard widget opens its feature full-screen, and
//  closing returns to the exact Home / Dashboard surface it was opened from.
//
//  The tile only forwards `WidgetPlacement.featureID`; the surface bookkeeping
//  is the existing `ShellStore` behaviour.
//

import Foundation
import SwiftUI
import Testing
@testable import Dash

private func placement(_ featureID: FeatureID, _ size: ComponentSize = .large) -> WidgetPlacement {
    WidgetPlacement(featureID: featureID, size: size, origin: GridPoint(column: 0, row: 0))
}

// MARK: - The tile forwards the right id

@MainActor
@Suite("WidgetHostView tap")
struct WidgetHostTapTests {

    @Test("tapping a widget requests its own feature id")
    func requestsFeatureID() {
        var requested: [FeatureID] = []
        WidgetHostView(
            placement: placement("maps"),
            registry: FeatureRegistry([]),
            onOpenFeature: { requested.append($0) }
        ).activate()

        #expect(requested == ["maps"])
    }

    @Test("different widgets request different feature ids")
    func distinctFeatureIDs() {
        var requested: [FeatureID] = []
        let sink: (FeatureID) -> Void = { requested.append($0) }
        let registry = FeatureRegistry([])

        WidgetHostView(placement: placement("maps"), registry: registry, onOpenFeature: sink).activate()
        WidgetHostView(placement: placement("speedometer", .compact), registry: registry, onOpenFeature: sink).activate()

        #expect(requested == ["maps", "speedometer"])
    }

    @Test("the tile is feature-agnostic — it forwards any id, known or not")
    func featureAgnostic() {
        var requested: [FeatureID] = []
        // A feature the registry has never heard of.
        WidgetHostView(
            placement: placement("future-widget"),
            registry: FeatureRegistry([]),
            onOpenFeature: { requested.append($0) }
        ).activate()

        #expect(requested == ["future-widget"])
    }
}

// MARK: - Open → close returns to the same surface

@MainActor
@Suite("Dashboard widget → full-screen navigation")
struct DashboardWidgetNavigationTests {

    /// Mirrors what `DashboardShell` wires: `onOpenFeature` → `ShellStore.openApp`.
    private func tapWidget(_ shell: ShellStore, _ id: FeatureID) {
        shell.openApp(id)
    }

    @Test("opening a widget from the Dashboard returns to the Dashboard")
    func returnsToDashboard() {
        let shell = ShellStore()
        shell.showDashboard()

        tapWidget(shell, "maps")
        #expect(shell.surface == .app("maps"))

        shell.closeApp()
        #expect(shell.surface == .dashboard)
    }

    @Test("opening a widget from Home returns to Home")
    func returnsToHome() {
        let shell = ShellStore()
        shell.showHome(page: 0)

        tapWidget(shell, "maps")
        #expect(shell.surface == .app("maps"))

        shell.closeApp()
        #expect(shell.surface == .home(page: 0))
    }

    @Test("two widget taps for different features each open the right feature, then return")
    func multipleFeatures() {
        let shell = ShellStore()
        shell.showDashboard()

        tapWidget(shell, "maps")
        #expect(shell.surface == .app("maps"))
        shell.closeApp()

        tapWidget(shell, "music")
        #expect(shell.surface == .app("music"))
        shell.closeApp()

        #expect(shell.surface == .dashboard)
    }

    @Test("the wired DashboardShell callback (openApp) remembers the Dashboard as the return surface")
    func returnSurfaceIsDashboard() {
        let shell = ShellStore()
        shell.showDashboard()
        shell.openApp("maps")          // the DashboardShell wiring: onOpenFeature -> openApp
        #expect(shell.returnSurface == .dashboard)
        shell.closeApp()
        #expect(shell.surface == .dashboard)
    }
}
