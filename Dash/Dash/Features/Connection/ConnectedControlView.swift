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

import SwiftUI

struct ConnectedControlView: View {

    /// Friendly name of the paired relay, if known.
    let deviceName: String?

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
            HStack(spacing: 6) {
                Image(systemName: "iphone.gen3")
                Text(label).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .tint(.primary)
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
        Color.black.opacity(0.8).ignoresSafeArea()
        ConnectedControlView(deviceName: "Saksham’s iPhone", onDisconnect: {}, onForget: {})
    }
}

#Preview("Unnamed") {
    ZStack {
        Color.black.opacity(0.8).ignoresSafeArea()
        ConnectedControlView(deviceName: nil, onDisconnect: {}, onForget: {})
    }
}
