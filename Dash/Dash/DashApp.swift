//
//  DashApp.swift
//  Dash
//
//  Created by Saksham Sharma on 2026-08-31.
//

import SwiftUI

@main
struct DashApp: App {

    /// Single source of truth for received location data.
    @StateObject private var locationStore: LocationStore

    /// Connection/session layer — owns the transport lifecycle and connection state.
    @StateObject private var connection: ConnectionCoordinator

    /// Pairing / known-device state. Independent of the current connection.
    @StateObject private var knownDevices: KnownDeviceStore

    init() {
        // Hand the Google Maps SDK its API key before any map view is created.
        GoogleMapsConfiguration.bootstrap()

        let store = LocationStore()
        _locationStore = StateObject(wrappedValue: store)
        _connection = StateObject(wrappedValue: ConnectionCoordinator(locationStore: store))
        _knownDevices = StateObject(wrappedValue: KnownDeviceStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationStore)
                .environmentObject(connection)
                .environmentObject(knownDevices)
                .task { connection.startSession() }
        }
    }
}
