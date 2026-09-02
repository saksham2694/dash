//
//  DashboardShell.swift
//  Dash
//
//  The CarPlay-style shell: a persistent left sidebar + a content area that
//  shows the active `ShellSurface`. This is the single layout/navigation owner
//  (spec §8) — feature views know nothing about it.
//
//  Shown by `RootView` whenever Dash is connected, in place of the old
//  full-screen `ContentView`.
//
//  M5.0 scope: the shell/feature seam only. The Home launcher is a simple
//  placeholder, the Dashboard space is a placeholder (the widget grid is
//  M5.2), and the only feature that opens full-screen is Map (its existing
//  `ContentView`, unchanged).
//

import SwiftUI

struct DashboardShell: View {

    @EnvironmentObject private var connection: ConnectionCoordinator
    @EnvironmentObject private var registry: FeatureRegistry

    @StateObject private var shell = ShellStore()

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
        switch shell.surface {
        case .home:
            HomePlaceholderView(
                manifests: registry.manifests,
                onOpen: { shell.openApp($0) }
            )
        case .dashboard:
            DashboardPlaceholderView()
        case .app(let id):
            if let feature = registry.feature(id) {
                feature.makeFullScreenView()
            } else {
                MissingFeatureView(id: id, onBack: { shell.closeApp() })
            }
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
