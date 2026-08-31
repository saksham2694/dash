//
//  ConnectionSetupView.swift
//  Dash
//
//  The connection / setup screen. `RootView` shows this whenever Dash has no
//  active connection to DashRelay; the dashboard (`ContentView`) is shown only
//  once connected.
//
//  This view is presentational: it renders the `ConnectionState` it is handed and
//  calls back for actions. The single source of connection state stays
//  `ConnectionCoordinator` — nothing is duplicated here.
//
//  Visual design is intentionally plain for now. No pairing controls yet.
//

import SwiftUI

struct ConnectionSetupView: View {

    /// Current connection state, owned by `ConnectionCoordinator`.
    let state: ConnectionState

    /// Stop looking / tear the session down (deliberate disconnect).
    let onDisconnect: () -> Void

    /// Start looking for DashRelay again (after a deliberate disconnect).
    let onReconnect: () -> Void

    var body: some View {
        let display = Display(state)

        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .font(.system(size: 52))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)

                        Text("Not Connected")
                            .font(.title2.weight(.semibold))

                        VStack(spacing: 10) {
                            if display.showsSpinner {
                                ProgressView()
                            }
                            Text(display.statusText)
                                .font(.headline)
                                .foregroundStyle(display.showsSpinner ? .primary : .secondary)
                                .multilineTextAlignment(.center)
                        }

                        Text("Dash shows your dashboard once it connects to the DashRelay app on your iPhone. Open DashRelay and keep both devices on the same Wi‑Fi network.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        actionButton(for: display.action)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: 460)
                    .padding(28)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(for action: Display.Action) -> some View {
        switch action {
        case .search:
            Button("Search for DashRelay", action: onReconnect)
                .buttonStyle(.borderedProminent)
        case .disconnect:
            Button("Disconnect", action: onDisconnect)
                .buttonStyle(.bordered)
                .tint(.red)
        case .none:
            EmptyView()
        }
    }
}

extension ConnectionSetupView {

    /// Everything the screen shows, derived purely from `ConnectionState`. Kept as
    /// a value type so the state → display mapping is unit-testable without SwiftUI.
    struct Display: Equatable {

        enum Action: Equatable {
            /// Offer to start looking for a relay (we are idle after a disconnect).
            case search
            /// Offer to stop the current attempt.
            case disconnect
            /// No action (we are connected — the dashboard is shown instead).
            case none
        }

        let showsSpinner: Bool
        let statusText: String
        let action: Action

        init(_ state: ConnectionState) {
            switch state {
            case .disconnected:
                showsSpinner = false
                statusText = "Dash isn’t looking for DashRelay right now."
                action = .search
            case .discovering:
                showsSpinner = true
                statusText = "Looking for DashRelay…"
                action = .disconnect
            case .connecting:
                showsSpinner = true
                statusText = "Connecting to DashRelay…"
                action = .disconnect
            case .connected:
                showsSpinner = false
                statusText = "Connected."
                action = .none
            }
        }
    }
}

#Preview("Disconnected") {
    ConnectionSetupView(state: .disconnected, onDisconnect: {}, onReconnect: {})
}

#Preview("Discovering") {
    ConnectionSetupView(state: .discovering, onDisconnect: {}, onReconnect: {})
}

#Preview("Connecting") {
    ConnectionSetupView(state: .connecting, onDisconnect: {}, onReconnect: {})
}
