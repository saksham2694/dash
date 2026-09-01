//
//  ConnectionSetupView.swift
//  Dash
//
//  The connection / setup screen. `RootView` shows this whenever Dash has no
//  active connection to DashRelay; the dashboard (`ContentView`) is shown only
//  once connected. The connected-state disconnect/forget control lives in
//  `ConnectedControlView`, overlaid on the dashboard.
//
//  This view is presentational. It renders a `Model` (connection state + the
//  discovered-relay list + the paired-device name) and calls back for actions —
//  it never touches `ConnectionCoordinator`, `KnownDeviceStore`, or the network.
//  The single source of connection state stays `ConnectionCoordinator`. The one
//  piece of local state is the "name this iPhone" prompt (presentation only).
//

import SwiftUI

struct ConnectionSetupView: View {

    /// Everything the screen needs, owned upstream by `ConnectionCoordinator`.
    let model: Model

    /// Stop the current search / attempt (deliberate). Keeps any pairing.
    let onStopSearching: () -> Void

    /// Start looking for DashRelay again (after stopping).
    let onSearch: () -> Void

    /// The user picked a relay from the list and named it — pair and connect.
    /// The second argument is the friendly name they typed (may be blank).
    let onPair: (DiscoveredRelay, String) -> Void

    /// Forget the currently paired relay (removes the relationship).
    let onForget: () -> Void

    /// The relay the user tapped and is now naming, if any. Presentation state.
    @State private var relayBeingNamed: DiscoveredRelay?
    @State private var nameDraft = ""

    var body: some View {
        let display = Display(model)

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

                        if !display.relayChoices.isEmpty {
                            relayList(display.relayChoices)
                        }

                        Text("Dash shows your dashboard once it connects to the DashRelay app on your iPhone. Open DashRelay and keep both devices on the same Wi‑Fi network.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        actionButton(for: display.action)
                            .padding(.top, 4)

                        if let forgetLabel = display.forgetLabel {
                            Button(forgetLabel, role: .destructive, action: onForget)
                                .font(.footnote)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: 460)
                    .padding(28)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
        }
        .alert(
            "Name this iPhone",
            isPresented: Binding(
                get: { relayBeingNamed != nil },
                set: { if !$0 { relayBeingNamed = nil } }
            ),
            presenting: relayBeingNamed
        ) { relay in
            TextField("iPhone", text: $nameDraft)
            Button("Pair") {
                onPair(relay, nameDraft)
                relayBeingNamed = nil
            }
            Button("Cancel", role: .cancel) { relayBeingNamed = nil }
        } message: { _ in
            Text("Give this iPhone a name you’ll recognise in Dash. Its identity stays the same whatever you call it.")
        }
    }

    @ViewBuilder
    private func relayList(_ relays: [DiscoveredRelay]) -> some View {
        VStack(spacing: 10) {
            ForEach(relays) { relay in
                Button {
                    nameDraft = relay.displayName
                    relayBeingNamed = relay
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(relay.displayName.isEmpty ? "DashRelay" : relay.displayName)
                                .font(.headline)
                            Text("ID \(relay.shortID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func actionButton(for action: Display.Action) -> some View {
        switch action {
        case .search:
            Button("Search for DashRelay", action: onSearch)
                .buttonStyle(.borderedProminent)
        case .stopSearching:
            Button("Stop Searching", action: onStopSearching)
                .buttonStyle(.bordered)
        case .none:
            EmptyView()
        }
    }
}

extension ConnectionSetupView {

    /// The inputs the screen renders from. A value type so the mapping below is
    /// unit-testable without SwiftUI.
    struct Model: Equatable {
        var state: ConnectionState
        /// Relays to offer for a first-time pick. Expected empty once paired.
        var offerableRelays: [DiscoveredRelay]
        /// Non-nil ⇒ a device is paired; its friendly name (for "looking for…",
        /// "connecting to…", and the Forget button).
        var pairedRelayName: String?

        init(state: ConnectionState, offerableRelays: [DiscoveredRelay] = [], pairedRelayName: String? = nil) {
            self.state = state
            self.offerableRelays = offerableRelays
            self.pairedRelayName = pairedRelayName
        }
    }

    /// Everything the screen shows, derived purely from `Model`.
    struct Display: Equatable {

        enum Action: Equatable {
            /// Offer to start looking for a relay (we are idle after stopping).
            case search
            /// Offer to stop the current search / connection attempt.
            case stopSearching
            /// No action (we are connected — the dashboard is shown instead).
            case none
        }

        let showsSpinner: Bool
        let statusText: String
        let relayChoices: [DiscoveredRelay]
        let action: Action
        /// Label for the "forget" button, or `nil` when nothing is paired.
        let forgetLabel: String?

        /// Whether a Forget affordance is shown. Retained for call-site clarity.
        var showsForget: Bool { forgetLabel != nil }

        init(_ model: Model) {
            forgetLabel = Self.forgetLabel(for: model.pairedRelayName)

            switch model.state {
            case .disconnected:
                showsSpinner = false
                statusText = "Dash isn’t looking for DashRelay right now."
                relayChoices = []
                action = .search

            case .connecting:
                showsSpinner = true
                statusText = model.pairedRelayName.map { "Connecting to \($0)…" } ?? "Connecting to DashRelay…"
                relayChoices = []
                action = .stopSearching

            case .connected:
                showsSpinner = false
                statusText = "Connected."
                relayChoices = []
                action = .none

            case .discovering:
                action = .stopSearching
                if let name = model.pairedRelayName {
                    // Paired but not in view — never offer to switch to a stranger.
                    showsSpinner = true
                    statusText = "Looking for \(name)…"
                    relayChoices = []
                } else if !model.offerableRelays.isEmpty {
                    showsSpinner = false
                    statusText = "Choose your iPhone to pair it with Dash:"
                    relayChoices = model.offerableRelays
                } else {
                    showsSpinner = true
                    statusText = "Looking for DashRelay…"
                    relayChoices = []
                }
            }
        }

        static func forgetLabel(for pairedRelayName: String?) -> String? {
            guard let name = pairedRelayName else { return nil }
            return name.isEmpty ? "Forget This iPhone" : "Forget \(name)"
        }
    }
}

#Preview("Discovering — nothing found") {
    ConnectionSetupView(
        model: .init(state: .discovering),
        onStopSearching: {}, onSearch: {}, onPair: { _, _ in }, onForget: {}
    )
}

#Preview("Discovering — pick a relay") {
    ConnectionSetupView(
        model: .init(state: .discovering, offerableRelays: [
            DiscoveredRelay(id: "AAAA1111", displayName: "Saksham’s iPhone"),
            DiscoveredRelay(id: "BBBB2222", displayName: "iPhone"),
        ]),
        onStopSearching: {}, onSearch: {}, onPair: { _, _ in }, onForget: {}
    )
}

#Preview("Looking for paired iPhone") {
    ConnectionSetupView(
        model: .init(state: .discovering, pairedRelayName: "Sak’s iPhone"),
        onStopSearching: {}, onSearch: {}, onPair: { _, _ in }, onForget: {}
    )
}

#Preview("Disconnected") {
    ConnectionSetupView(
        model: .init(state: .disconnected, pairedRelayName: "Sak’s iPhone"),
        onStopSearching: {}, onSearch: {}, onPair: { _, _ in }, onForget: {}
    )
}
