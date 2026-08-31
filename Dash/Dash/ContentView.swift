//
//  ContentView.swift
//  Dash
//
//  Created by Saksham Sharma on 2026-08-31.
//
//  For now this is just the full-screen map, so the Google Maps integration can be
//  exercised end to end. The real CarPlay-style dashboard layout comes later and
//  will embed `DashMapView` as one tile.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var locationStore: LocationStore
    @StateObject private var mapViewModel = MapViewModel()

    var body: some View {
        DashMapView(viewModel: mapViewModel, location: locationStore.latestPacket)
            .ignoresSafeArea()
    }
}

#Preview {
    let _ = GoogleMapsConfiguration.bootstrap()
    ContentView()
        .environmentObject(LocationStore())
}
