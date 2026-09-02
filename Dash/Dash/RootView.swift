//
//  RootView.swift
//  Dash
//
//  The single place connection state gates the UI: the CarPlay-style shell
//  (`DashboardShell`) is shown only when there is an active connection to
//  DashRelay; otherwise the connection / setup screen. Feature views never see
//  connection state.
//
//  This is the container that reads `ConnectionCoordinator` and wires the
//  presentational connection setup screen's pairing actions back to it. While
//  connected, Disconnect / Forget live in the shell's sidebar
//  (`ConnectedControlView`), not as an overlay here.
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var connection: ConnectionCoordinator

    var body: some View {
        if connection.isConnected {
            DashboardShell()
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
