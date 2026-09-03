//
//  DashboardShell.swift
//  Dash
//
//  The CarPlay-style shell: a persistent left sidebar + a content area that
//  shows the active `ShellSurface`. This is the single layout/navigation owner
//  (spec §8) — feature views know nothing about it.
//
//  Shown by `RootView` whenever Dash is connected, in place of the old
//  full-screen map view.
//
//  Scope so far: the shell/feature seam, the single widget dashboard, real Map
//  dashboard components (M5.2.x), and the App-Home launcher (M5.3.x). The
//  Dashboard and the Home pages form one horizontal sequence of spaces driven
//  by `SpacePagerView`; a full-screen `.app` is shown instead of that pager.
//  Both spaces forward a tapped tile's `featureID` through an `onOpenFeature`
//  callback → `ShellStore.openApp`; `closeApp()` returns to the exact Home page
//  / the Dashboard it was opened from. Feature runtime state stays app-scoped
//  (M5.1).
//

import SwiftUI

struct DashboardShell: View {

    @EnvironmentObject private var connection: ConnectionCoordinator
    @EnvironmentObject private var registry: FeatureRegistry
    @EnvironmentObject private var layoutStore: DashboardLayoutStore
    @EnvironmentObject private var homeLayout: HomeLayoutStore

    @StateObject private var shell = ShellStore()

    /// The Dashboard's transient edit-mode flag (M5.4.1). Owned here — the shell
    /// presentation layer — so it survives Home/Dashboard paging and is never a
    /// navigation concern. Starts in normal mode.
    @StateObject private var dashboardEdit = DashboardEditModel()

    /// The one grid the dashboard lays out on. Swappable in a single place.
    private let grid = DashboardGrid.standard

    /// Presentation-only Home tiles for apps not built yet (not registered
    /// features, not persisted). One place to drop them until each ships.
    private static let comingSoonApps: [HomeComingSoonApp] = [
        .init(title: "Music", symbolName: "music.note"),
        .init(title: "Speedometer", symbolName: "gauge.open.with.lines.needle.33percent"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                shell: shell,
                manifests: registry.manifests,
                connectedDeviceName: connection.pairedRelayDisplayName,
                onDisconnect: { connection.disconnect() },
                onForget: { connection.forgetPairedRelay() }
            )

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: shell.surface)
        .animation(.easeInOut(duration: 0.2), value: shell.sidebarCollapsed)
    }

    @ViewBuilder
    private var content: some View {
        if case .app(let id) = shell.surface {
            if let feature = registry.feature(id) {
                feature.makeFullScreenView()
            } else {
                MissingFeatureView(id: id, onBack: { shell.closeApp() })
            }
        } else {
            // The Dashboard and the Home pages are one horizontal sequence of
            // spaces, driven by a single shell-level pager.
            SpacePagerView(
                shell: shell,
                homeLayout: homeLayout,
                dashboardLayout: layoutStore,
                dashboardEdit: dashboardEdit,
                registry: registry,
                grid: grid,
                comingSoon: Self.comingSoonApps
            )
        }
    }
}

/// Shown if `ShellSurface.app` names a feature that isn't registered (e.g. a
/// stale persisted surface after a feature is removed — relevant once the
/// surface is persisted).
private struct MissingFeatureView: View {
    let id: FeatureID
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.app.dashed").font(.largeTitle)
            Text("“\(id)” isn’t available").font(.headline)
            Button("Back to Home", action: onBack)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
