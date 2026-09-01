//
//  RootView.swift
//  Dash
//
//  The single place connection state gates the UI: the dashboard (`ContentView`)
//  is shown only when there is an active connection to DashRelay; otherwise the
//  connection / setup screen. Feature views never see connection state.
//
//  This is the container that reads `ConnectionCoordinator` and wires the
//  presentational connection views' actions back to it — the setup screen's
//  pairing actions, and (while connected) the `ConnectedControlView` overlay's
//  Disconnect / Forget.
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var connection: ConnectionCoordinator

    var body: some View {
        if connection.isConnected {
            ContentView()
                .overlay(alignment: .topTrailing) {
                    ConnectedControlView(
                        deviceName: connection.pairedRelayDisplayName,
                        onDisconnect: { connection.disconnect() },
                        onForget: { connection.forgetPairedRelay() }
                    )
                    .padding(12)
                }
        } else {
            ConnectionSetupView(
                model: .init(
                    state: connection.connectionState,
                    offerableRelays: connection.offerableRelays,
                    pairedRelayName: connection.pairedRelayName
                ),
                onStopSearching: { connection.disconnect() },
                onSearch: { connection.startSession() },
                onPair: { relay, name in connection.pairAndConnect(to: relay, named: name) },
                onForget: { connection.forgetPairedRelay() }
            )
        }
    }
}
