//
//  DashboardShell.swift
//  Dash
//
//  The CarPlay-style shell: a fixed left rail (`DashSidebar`) + a content area
//  that shows the active `ShellSurface`, composited as ONE rounded, inset
//  container. The wallpaper (`DashShellBackground`) is the *background of that
//  container* — it is clipped to the shell's rounded corners and shares the
//  shell's inset, so it never appears outside the shell or behind the status-bar
//  area. Shell inset + corner radius come from `DashMetrics.shell*` (one source
//  of truth) so the wallpaper and the shell geometry cannot drift apart.
//
//  This is the single layout/navigation owner (spec §8) — feature views know
//  nothing about it. The iPadOS status bar / home indicator are hidden
//  (automotive full screen); the rail's own clock is the time display.
//
//  Keyboard: the whole SwiftUI tree opts out of keyboard safe-area avoidance
//  (`DashApp` applies `.ignoresSafeArea(.keyboard)` at the hosting-view root —
//  the ancestor that absorbs the keyboard inset). The shell re-asserts it here
//  directly on its fill frame as a belt-and-suspenders anchor: when the Maps
//  search field is focused the keyboard overlays the lower shell area but the
//  rail top, the wallpaper, the rounded bounds and the border do not move,
//  resize, or clip. Dismissing the keyboard is a no-op — nothing was displaced.
//
//  Shown by `RootView` whenever Dash is connected, in place of the old
//  full-screen map view.
//
//  The Dashboard and the Home pages form one horizontal sequence of spaces
//  driven by `SpacePagerView`; a full-screen `.app` is shown instead of that
//  pager. Both spaces forward a tapped tile's `featureID` through an
//  `onOpenFeature` callback → `ShellStore.openApp`; `closeApp()` returns to the
//  exact Home page / the Dashboard it was opened from. Feature runtime state
//  stays app-scoped (M5.1).
//

import SwiftUI

struct DashboardShell: View {

    @EnvironmentObject private var connection: ConnectionCoordinator
    @EnvironmentObject private var registry: FeatureRegistry
    @EnvironmentObject private var dashboards: DashboardCollectionStore
    @EnvironmentObject private var homeLayout: HomeLayoutStore
    @EnvironmentObject private var locationStore: LocationStore
    @EnvironmentObject private var deviceStatus: DeviceStatusStore

    @StateObject private var shell = ShellStore()

    /// The Dashboard's transient edit-mode flag (M5.4.1). Owned here — the shell
    /// presentation layer — so it survives Home/Dashboard paging and is never a
    /// navigation concern. Starts in normal mode.
    @StateObject private var dashboardEdit = DashboardEditModel()

    /// The one grid the dashboard lays out on. Swappable in a single place.
    private let grid = DashboardGrid.standard

    var body: some View {
        shellContainer
            .logsKeyboardGeometry("shell-container")
            .padding(DashMetrics.shellOuterInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Defence in depth (the real fix is `stopsRootKeyboardAvoidance()` at
            // the app root): opt the fill frame out of the keyboard safe area so
            // it is proposed the keyboard-inclusive height.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .logsKeyboardGeometry("shell-root")
            .animation(.easeInOut(duration: 0.25), value: shell.surface)
    }

    /// Rail + content as one rounded, clipped panel — the "automotive display".
    /// The wallpaper is this panel's background, so it is clipped to the same
    /// rounded rect and shares the same bounds.
    private var shellContainer: some View {
        let shape = RoundedRectangle(cornerRadius: DashMetrics.shellCornerRadius, style: .continuous)
        return HStack(spacing: 0) {
            DashSidebar(
                shell: shell,
                connection: connection,
                location: locationStore,
                deviceStatus: deviceStatus,
                manifests: registry.manifests,
                onDisconnect: { connection.disconnect() },
                onForget: { connection.forgetPairedRelay() }
            )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DashShellBackground())
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: DashMetrics.hairline))
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
                dashboards: dashboards,
                dashboardEdit: dashboardEdit,
                registry: registry,
                grid: grid
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
        VStack(spacing: DashMetrics.spacingMedium) {
            Image(systemName: "questionmark.app.dashed")
                .font(.system(size: DashMetrics.statusGlyph))
                .foregroundStyle(Color.dashTextSecondary)
            Text("“\(id)” isn’t available")
                .font(.dashTitle)
                .foregroundStyle(Color.dashTextPrimary)
            Button("Back to Home", action: onBack)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
