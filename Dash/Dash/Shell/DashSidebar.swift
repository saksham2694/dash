//
//  DashSidebar.swift
//  Dash
//
//  Dash's persistent navigation/status rail — a fixed, always-visible strip on
//  the left, styled after the CarPlay rail (there is no expand / collapse).
//
//    TOP     — a status cluster, VERTICALLY stacked: the current time (a small
//              one-line status element, not a title), the paired-iPhone chip
//              (tap → Disconnect / Forget), a GPS-state dot, and the iPhone
//              battery (real telemetry from DashRelay — M5.7).
//    MIDDLE  — recent / registered feature icons (Maps today; new features
//              appear here automatically from `FeatureRegistry`). Icon-only.
//    BOTTOM  — ONE control that toggles between the Dashboard and Home.
//
//  It drives navigation only through `ShellStore` and never becomes a second
//  page-navigation system (the horizontal swipe pager is untouched). It reads
//  `ConnectionCoordinator` / `LocationStore` for status but owns none of it.
//

import DashShared
import SwiftUI

struct DashSidebar: View {

    @ObservedObject var shell: ShellStore
    @ObservedObject var connection: ConnectionCoordinator
    @ObservedObject var location: LocationStore
    @ObservedObject var deviceStatus: DeviceStatusStore

    /// Registered features, in order — the rail's app icons.
    let manifests: [FeatureManifest]

    let onDisconnect: () -> Void
    let onForget: () -> Void

    // MARK: - Pure helpers (testable)

    /// Which rail app is currently selected (a full-screen feature), if any.
    nonisolated static func selectedApp(for surface: ShellSurface) -> FeatureID? {
        if case .app(let id) = surface { return id }
        return nil
    }

    /// The space the Home/Dashboard toggle would move to from `surface`.
    nonisolated static func toggleDestination(for surface: ShellSurface) -> ToggleDestination {
        switch surface {
        case .dashboard:      return .home
        case .home, .app:     return .dashboard
        }
    }

    enum ToggleDestination: Equatable {
        case home, dashboard

        var symbol: String {
            switch self {
            case .home:      return "square.grid.2x2.fill"
            case .dashboard: return "rectangle.grid.1x2.fill"
            }
        }
        var accessibilityLabel: String {
            switch self {
            case .home:      return "Go to Home"
            case .dashboard: return "Go to the Dashboard"
            }
        }
    }

    // MARK: - Body

    private var selectedApp: FeatureID? { Self.selectedApp(for: shell.surface) }

    var body: some View {
        VStack(spacing: 0) {
            DashStatusCluster(
                connection: connection,
                location: location,
                deviceStatus: deviceStatus,
                onDisconnect: onDisconnect,
                onForget: onForget
            )

            Divider()
                .overlay(Color.white.opacity(0.10))
                .padding(.vertical, DashMetrics.spacingMedium)

            DashRecentApps(
                manifests: manifests,
                selectedID: selectedApp,
                onOpen: { shell.openApp($0) }
            )

            Spacer(minLength: DashMetrics.spacingMedium)

            DashHomeDashboardToggle(destination: Self.toggleDestination(for: shell.surface)) {
                shell.toggleHomeDashboard()
            }
        }
        .padding(.vertical, DashMetrics.spacingLarge)
        .padding(.horizontal, DashMetrics.railInset)
        .frame(width: DashMetrics.railWidth)
        .frame(maxHeight: .infinity)
        .background {
            // Translucent grey automotive glass over `DashShellBackground` — a
            // thin material with only a light neutral wash so the wallpaper
            // genuinely bleeds through. Not opaque black, no frosted-card shine.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.dashRailTint)
                LinearGradient(
                    colors: [Color.dashGlassHighlight.opacity(0.5), .clear],
                    startPoint: .top, endPoint: .center
                )
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: DashMetrics.hairline)
            }
        }
    }
}

// MARK: - Status cluster

private struct DashStatusCluster: View {

    @ObservedObject var connection: ConnectionCoordinator
    @ObservedObject var location: LocationStore
    @ObservedObject var deviceStatus: DeviceStatusStore
    let onDisconnect: () -> Void
    let onForget: () -> Void

    private var battery: DashBatteryStatus {
        DashBatteryFormatter.status(
            percent: deviceStatus.batteryPercent,
            state: deviceStatus.batteryState,
            freshness: deviceStatus.freshness
        )
    }

    var body: some View {
        VStack(spacing: DashMetrics.spacingSmall) {
            // Time — a small one-line status element, not a title.
            TimelineView(.everyMinute) { context in
                Text(DashStatusModel.timeText(context.date))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.dashTextPrimary)
                    .frame(maxWidth: .infinity)
            }

            // Phone connection chip (tap → Disconnect / Forget).
            ConnectedControlView(
                deviceName: connection.connectedDisplayName ?? connection.pairedRelayDisplayName,
                collapsed: true,
                onDisconnect: onDisconnect,
                onForget: onForget
            )

            // GPS state — a dot + short label, no navigation glyph.
            statusRow(
                dot: DashStatusModel.gpsColor(isSignalLost: location.isSignalLost, hasFix: location.hasFix),
                text: DashStatusModel.gpsShortLabel(isSignalLost: location.isSignalLost, hasFix: location.hasFix)
            )
            .accessibilityLabel(DashStatusModel.gpsLabel(isSignalLost: location.isSignalLost, hasFix: location.hasFix))

            // iPhone battery — real telemetry from DashRelay (M5.7). An
            // intentional unavailable glyph when no reading has arrived.
            batteryRow
        }
        .frame(maxWidth: .infinity)
    }

    private var batteryRow: some View {
        HStack(spacing: DashMetrics.spacingTight) {
            Image(systemName: battery.symbolName)
                .font(.system(size: 13, weight: .semibold))
            if let text = battery.text {
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .foregroundStyle(battery.isDimmed ? Color.dashTextTertiary : Color.dashTextSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(battery.accessibilityLabel)
    }

    private func statusRow(dot: Color, text: String) -> some View {
        HStack(spacing: DashMetrics.spacingTight) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.dashTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 22)
    }

}

// MARK: - Status cluster model (pure, testable)

/// The rail status cluster's content decisions, kept out of the view so the
/// "time is one line / rows are stacked in this order" assumptions are unit
/// tested (M5.5.2b §20).
enum DashStatusModel {

    /// The vertical row order of the status cluster, top → bottom.
    enum Row: CaseIterable, Equatable {
        case time, phone, gps, battery
    }

    /// The fixed top-to-bottom order the cluster renders.
    static let rowOrder: [Row] = [.time, .phone, .gps, .battery]

    static func timeText(_ date: Date, locale: Locale = .current) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    static func gpsColor(isSignalLost: Bool, hasFix: Bool) -> Color {
        if isSignalLost { return Color.dashDanger }
        return hasFix ? Color.dashPositive : Color.dashTextTertiary
    }

    static func gpsShortLabel(isSignalLost: Bool, hasFix: Bool) -> String {
        if isSignalLost { return "No GPS" }
        return hasFix ? "GPS" : "GPS…"
    }

    static func gpsLabel(isSignalLost: Bool, hasFix: Bool) -> String {
        if isSignalLost { return "GPS signal lost" }
        return hasFix ? "GPS active" : "Acquiring GPS"
    }
}

// MARK: - Recent apps

private struct DashRecentApps: View {

    let manifests: [FeatureManifest]
    let selectedID: FeatureID?
    let onOpen: (FeatureID) -> Void

    var body: some View {
        VStack(spacing: DashMetrics.railIconGap) {
            ForEach(manifests) { manifest in
                DashRailIconButton(
                    manifest: manifest,
                    isSelected: manifest.id == selectedID,
                    action: { onOpen(manifest.id) }
                )
            }
        }
    }
}

/// A single rail app icon in its selectable slot.
struct DashRailIconButton: View {

    let manifest: FeatureManifest
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DashAppIcon(manifest: manifest, size: DashMetrics.railIconSize)
                .frame(width: DashMetrics.railSlotSize, height: DashMetrics.railSlotSize)
                .background {
                    // The icon sits directly on the rail. The selected state is
                    // only a soft translucent halo behind it — no hard box, no
                    // accent stroke framing every icon.
                    if isSelected {
                        RoundedRectangle(cornerRadius: DashMetrics.controlCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    }
                }
                .overlay(alignment: .leading) {
                    // A small leading pip marks the active app, CarPlay-style.
                    if isSelected {
                        Capsule()
                            .fill(Color.dashTextPrimary)
                            .frame(width: 3, height: DashMetrics.railIconSize * 0.5)
                            .offset(x: -DashMetrics.railInset + 2)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: DashMetrics.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(.dashPress)
        .accessibilityLabel(manifest.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Home / Dashboard toggle

private struct DashHomeDashboardToggle: View {

    let destination: DashSidebar.ToggleDestination
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: destination.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.dashTextPrimary)
                .frame(width: DashMetrics.railSlotSize, height: DashMetrics.railSlotSize)
                .background(
                    RoundedRectangle(cornerRadius: DashMetrics.controlCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DashMetrics.controlCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: DashMetrics.hairline)
                )
                .contentShape(RoundedRectangle(cornerRadius: DashMetrics.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(.dashPress)
        .accessibilityLabel(destination.accessibilityLabel)
    }
}
