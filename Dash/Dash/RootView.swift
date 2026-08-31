//
//  RootView.swift
//  Dash
//
//  The single place connection state gates the UI: the dashboard is shown only
//  when there is an active connection to DashRelay. Feature views (ContentView,
//  the map, etc.) never see connection state.
//
//  The not-connected view here is a deliberate throwaway placeholder — the real
//  setup / connection / pairing screens are a later milestone.
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var connection: ConnectionCoordinator

    var body: some View {
        if connection.isConnected {
            ContentView()
        } else {
            ConnectionPlaceholderView(state: connection.connectionState)
        }
    }
}

/// Minimal placeholder shown until a relay connection exists. Not the real UI.
private struct ConnectionPlaceholderView: View {

    let state: ConnectionState

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var message: String {
        switch state {
        case .disconnected: "Not connected to DashRelay"
        case .discovering:  "Looking for DashRelay…"
        case .connecting:   "Connecting…"
        case .connected:    ""
        }
    }
}
