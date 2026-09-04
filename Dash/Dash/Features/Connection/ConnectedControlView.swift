//
//  ConnectedControlView.swift
//  Dash
//
//  A compact control `RootView` overlays on the dashboard while Dash is
//  connected. It names the paired iPhone and offers two clearly distinct
//  actions:
//
//    • Disconnect — ends the active session, keeps the pairing.
//    • Forget <name> — removes the pairing entirely (first-time setup again).
//
//  Presentational: it takes the paired device name plus the two closures and
//  holds only local presentation state (whether the dialog is open). All session
//  and pairing logic stays in `ConnectionCoordinator`.
//
//  M5.5.2: styled to sit in the navigation rail — a solid `dashCard` chip (not a
//  frosted capsule), a small `dashPositive` "connected" dot, and an icon-only
//  form when the rail is collapsed. Behaviour (the Disconnect / Forget dialog)
//  is unchanged.
//

import SwiftUI

struct ConnectedControlView: View {

    /// Friendly name of the paired relay, if known.
    let deviceName: String?

    /// Whether the rail is collapsed (icon-only form).
    var collapsed: Bool = false

    /// End the active session; keep the pairing.
    let onDisconnect: () -> Void

    /// Remove the pairing entirely.
    let onForget: () -> Void

    @State private var showingOptions = false

    /// What to call the device in the UI when no friendly name is set.
    static func deviceLabel(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "DashRelay" }
        return name
    }

    private var label: String { Self.deviceLabel(deviceName) }

    var body: some View {
        Button {
            showingOptions = true
        } label: {
            HStack(spacing: DashMetrics.spacingTight) {
                Image(systemName: "iphone.gen3")
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(Color.dashPositive)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -1)
                    }
                if !collapsed {
                    Text(label).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .font(.dashLabel)
            .foregroundStyle(Color.dashTextPrimary)
            .padding(.horizontal, DashMetrics.spacingSmall)
            .frame(maxWidth: .infinity)
            .frame(height: DashMetrics.controlHeight)
            .background(
                Color.dashCard,
                in: RoundedRectangle(cornerRadius: DashMetrics.controlCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.dashPress)
        .accessibilityLabel(collapsed ? "\(label), connected" : label)
        .accessibilityHint("Disconnect or forget this iPhone")
        .confirmationDialog(label, isPresented: $showingOptions, titleVisibility: .visible) {
            Button("Disconnect") { onDisconnect() }
            Button("Forget \(label)", role: .destructive) { onForget() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Disconnect ends this session but keeps \(label) paired. Forget removes the pairing.")
        }
    }
}

#Preview("Named") {
    ZStack {
        Color.dashSurface.ignoresSafeArea()
        ConnectedControlView(deviceName: "Saksham’s iPhone", onDisconnect: {}, onForget: {})
    }
}

#Preview("Collapsed") {
    ZStack {
        Color.dashSurface.ignoresSafeArea()
        ConnectedControlView(deviceName: "Saksham’s iPhone", collapsed: true, onDisconnect: {}, onForget: {})
    }
}

#Preview("Unnamed") {
    ZStack {
        Color.dashSurface.ignoresSafeArea()
        ConnectedControlView(deviceName: nil, onDisconnect: {}, onForget: {})
    }
}
