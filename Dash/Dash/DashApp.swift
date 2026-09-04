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

    /// Persisted widget-dashboard arrangement. Seeded with a starter layout for
    /// the Map feature (the shell stays feature-agnostic; the seed is wired
    /// here, next to the feature registry).
    @StateObject private var dashboardLayout: DashboardLayoutStore

    /// Persisted App-Home arrangement. Seeded from the registered feature ids.
    @StateObject private var homeLayout: HomeLayoutStore

    /// Persisted shell wallpaper selection. Read by `DashShellBackground` on both
    /// the Dashboard and Home; a future Settings feature changes it.
    @StateObject private var wallpaper = WallpaperStore()

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

        let features = FeatureRegistry.makeDefault()
        _registry = StateObject(wrappedValue: features)
        _dashboardLayout = StateObject(wrappedValue: DashboardLayoutStore(seed: .starter(featureID: MapFeature.id)))
        _homeLayout = StateObject(wrappedValue: HomeLayoutStore(
            seed: .paginate(featureIDs: features.manifests.map(\.id), capacity: HomeGrid.capacity)
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationStore)
                .environmentObject(connection)
                .environmentObject(knownDevices)
                .environmentObject(registry)
                .environmentObject(dashboardLayout)
                .environmentObject(homeLayout)
                .environmentObject(wallpaper)
                .task { connection.startSession() }
                // Dash is a fixed full-screen automotive surface. The software
                // keyboard (Maps search) must overlay content, never resize or
                // reposition the shell. `.ignoresSafeArea(.keyboard)` is the
                // SwiftUI-layout opt-out; it is kept as defence in depth, but on
                // the physical iPad it does NOT stop the App-lifecycle root
                // `_UIHostingView` from resizing itself for the keyboard — so the
                // real fix neutralises that handler on the hosting view directly.
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .stopsRootKeyboardAvoidance()
        }
    }
}
