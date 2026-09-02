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

    /// The features the CarPlay-style shell can show. Fixed for the app's
    /// lifetime; declared in `FeatureRegistry.makeDefault()`.
    @StateObject private var registry: FeatureRegistry

    init() {
        // Hand the Google Maps + Places SDKs their API key before any map view
        // or place lookup happens.
        GoogleMapsConfiguration.bootstrap()
        GooglePlacesConfiguration.bootstrap()

        let store = LocationStore()
        let known = KnownDeviceStore()
        _locationStore = StateObject(wrappedValue: store)
        _knownDevices = StateObject(wrappedValue: known)
        _connection = StateObject(wrappedValue: ConnectionCoordinator(locationStore: store, knownDevices: known))
        _registry = StateObject(wrappedValue: .makeDefault())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationStore)
                .environmentObject(connection)
                .environmentObject(knownDevices)
                .environmentObject(registry)
                .task { connection.startSession() }
        }
    }
}
