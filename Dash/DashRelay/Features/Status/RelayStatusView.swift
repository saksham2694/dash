//
//  RelayStatusView.swift
//  DashRelay
//
//  The first connection/status screen for DashRelay. It shows whether the relay
//  is stopped, waiting for a Dash iPad, or connected — and offers Start / Stop
//  Sharing / Disconnect.
//
//  `RelaySessionController` is the single source of truth. `RelayStatusScreen` is
//  the container that reads it from the environment; `RelayStatusView` is
//  presentational (state + action closures in) and holds no copy of the state.
//  All networking / GPS lifecycle stays in `RelaySessionController`.
//
//  Visuals are intentionally plain for now. No pairing controls.
//

import SwiftUI

/// The DashRelay root. Wires the session to the presentational status view.
struct RelayStatusScreen: View {

    @EnvironmentObject private var session: RelaySessionController

    var body: some View {
        RelayStatusView(
            state: session.state,
            onStart: { session.start() },
            onStop: { session.stop() }
        )
    }
}

struct RelayStatusView: View {

    /// Current session state, owned by `RelaySessionController`.
    let state: RelaySessionController.State

    /// Begin advertising + sharing location (recover from a stopped state).
    let onStart: () -> Void

    /// Stop the session — ends advertising and GPS via the session layer. Used
    /// for both "Stop Sharing" (while waiting) and "Disconnect" (while connected).
    let onStop: () -> Void

    var body: some View {
        let display = Display(state)

        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: display.symbolName)
                            .font(.system(size: 52))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(display.tint)

                        Text(display.title)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)

                        if display.showsActivity {
                            ProgressView()
                        }

                        Text(display.message)
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
        case .start:
            Button("Start", action: onStart)
                .buttonStyle(.borderedProminent)
        case .stopSharing:
            Button("Stop Sharing", action: onStop)
                .buttonStyle(.bordered)
        case .disconnect:
            Button("Disconnect", action: onStop)
                .buttonStyle(.bordered)
                .tint(.red)
        case .none:
            EmptyView()
        }
    }
}

extension RelayStatusView {

    /// Everything the screen shows, derived purely from the session state. A value
    /// type so the state → screen mapping is unit-testable without SwiftUI.
    struct Display: Equatable {

        enum Action: Equatable {
            /// Offer to start the relay (we are stopped).
            case start
            /// Offer to stop advertising while no iPad has connected yet.
            case stopSharing
            /// Offer to disconnect (a dashboard is connected).
            case disconnect
            /// No action.
            case none
        }

        let symbolName: String
        let title: String
        let message: String
        let showsActivity: Bool
        let action: Action

        var tint: Color {
            switch action {
            case .disconnect: .green    // connected
            case .start: .secondary     // stopped
            case .stopSharing: .accentColor  // waiting
            case .none: .accentColor
            }
        }

        init(_ state: RelaySessionController.State) {
            switch state {
            case .stopped:
                symbolName = "pause.circle"
                title = "Relay Stopped"
                message = "DashRelay isn’t sharing your location. Tap Start to wait for your Dash iPad."
                showsActivity = false
                action = .start
            case .waiting:
                symbolName = "antenna.radiowaves.left.and.right"
                title = "Ready to Connect"
                message = "DashRelay is sharing your iPhone’s location on this Wi‑Fi network. Open Dash on your iPad to connect — or tap Stop Sharing if you’re done."
                showsActivity = true
                action = .stopSharing
            case .connected:
                symbolName = "checkmark.circle.fill"
                title = "Connected"
                message = "Your Dash iPad is connected and receiving GPS. Keep DashRelay open while you drive."
                showsActivity = false
                action = .disconnect
            }
        }
    }
}

#Preview("Stopped") {
    RelayStatusView(state: .stopped, onStart: {}, onStop: {})
}

#Preview("Waiting") {
    RelayStatusView(state: .waiting, onStart: {}, onStop: {})
}

#Preview("Connected") {
    RelayStatusView(state: .connected, onStart: {}, onStop: {})
}
