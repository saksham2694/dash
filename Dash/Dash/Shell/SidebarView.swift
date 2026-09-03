//
//  SidebarView.swift
//  Dash
//
//  The persistent CarPlay-style navigation rail: Home, Dashboard, then one
//  button per registered feature, with the connected-device control pinned to
//  the bottom.
//
//  Presentational: it takes `FeatureManifest`s (never `DashFeature` objects or
//  their view models) and drives navigation through `ShellStore`. It holds no
//  connection/pairing state — `ConnectedControlView` (unchanged) still owns
//  Disconnect / Forget; only its placement moved here from `RootView`.
//

import SwiftUI

struct SidebarView: View {

    @ObservedObject var shell: ShellStore

    /// Registered features, in order — one nav button each.
    let manifests: [FeatureManifest]

    /// Friendly name of the paired relay, for the bottom control.
    let connectedDeviceName: String?

    /// Preserved exactly from the old `RootView` overlay.
    let onDisconnect: () -> Void
    let onForget: () -> Void

    private var isHome: Bool { if case .home = shell.surface { return true }; return false }
    private var isDashboard: Bool { if case .dashboard = shell.surface { return true }; return false }
    private var width: CGFloat { shell.sidebarCollapsed ? 76 : 108 }

    var body: some View {
        VStack(spacing: 12) {
            SidebarButton(
                symbol: "square.grid.2x2.fill",
                label: "Home",
                isSelected: isHome,
                collapsed: shell.sidebarCollapsed,
                action: { shell.showHome() }
            )
            SidebarButton(
                symbol: "rectangle.3.group.fill",
                label: "Dashboard",
                isSelected: isDashboard,
                collapsed: shell.sidebarCollapsed,
                action: { shell.showDashboard() }
            )

            Rectangle()
                .fill(Color.dashSeparator)
                .frame(height: DashMetrics.hairline)
                .padding(.horizontal, 18)
                .padding(.vertical, 2)

            ForEach(manifests) { manifest in
                SidebarButton(
                    symbol: manifest.symbolName,
                    label: manifest.title,
                    isSelected: shell.surface == .app(manifest.id),
                    collapsed: shell.sidebarCollapsed,
                    action: { shell.openApp(manifest.id) }
                )
            }

            Spacer(minLength: 8)

            ConnectedControlView(
                deviceName: connectedDeviceName,
                onDisconnect: onDisconnect,
                onForget: onForget
            )

            Button {
                shell.toggleSidebar()
            } label: {
                Image(systemName: shell.sidebarCollapsed ? "chevron.right" : "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 40, height: 32)
                    .background(
                        Color.dashCard,
                        in: RoundedRectangle(cornerRadius: DashMetrics.controlCornerRadius)
                    )
            }
            .buttonStyle(.plain)
            .tint(Color.dashTextPrimary)
            .accessibilityLabel(shell.sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
        }
        .padding(.vertical, 18)
        .padding(.horizontal, DashMetrics.spacingSmall)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Color.dashSurface.ignoresSafeArea())
    }
}

/// One large, glanceable nav button. Icon-only when the sidebar is collapsed.
private struct SidebarButton: View {

    let symbol: String
    let label: String
    let isSelected: Bool
    let collapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(height: 26)
                if !collapsed {
                    Text(label)
                        .font(.dashLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: collapsed ? 52 : 62)
            .background(
                RoundedRectangle(cornerRadius: DashMetrics.controlCornerRadius)
                    .fill(isSelected ? Color.dashAccent : Color.dashCard)
            )
            .foregroundStyle(isSelected ? Color.dashOnAccent : Color.dashTextPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
