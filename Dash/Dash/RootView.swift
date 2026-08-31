//
//  RootView.swift
//  Dash
//
//  The single place connection state gates the UI: the dashboard (`ContentView`)
//  is shown only when there is an active connection to DashRelay; otherwise the
//  connection / setup screen. Feature views never see connection state.
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var connection: ConnectionCoordinator

    var body: some View {
        if connection.isConnected {
            ContentView()
        } else {
            ConnectionSetupView(
                state: connection.connectionState,
                onDisconnect: { connection.disconnect() },
                onReconnect: { connection.startSession() }
            )
        }
    }
}
