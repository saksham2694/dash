//
//  DashApp.swift
//  Dash
//
//  Created by Saksham Sharma on 2026-08-31.
//

import SwiftUI

@main
struct DashApp: App {
    /// The single source of truth for location, owned for the app's lifetime.
    /// Creating it wires the `LocationReceiver` callbacks; `.task` below starts it.
    @StateObject private var locationStore = LocationStore()

    init() {
        // Hand the Google Maps SDK its API key before any map view is created.
        GoogleMapsConfiguration.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationStore)
                .task { locationStore.start() }
        }
    }
}
