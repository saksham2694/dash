//
//  ContentView.swift
//  Dash
//
//  Created by Saksham Sharma on 2026-08-31.
//
//  For now this is the full-screen map plus the destination-search overlay, so
//  the Map feature can be exercised end to end. The real CarPlay-style dashboard
//  layout comes later and will embed `DashMapView` as one tile.
//
//  This is the composition point for the Map feature: it owns the map view model,
//  the search view model, and the destination store, and wires them together.
//  None of those three know about each other.
//

import DashShared
import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var locationStore: LocationStore

    @StateObject private var mapViewModel = MapViewModel()
    @StateObject private var destinationStore = DestinationStore()
    @StateObject private var searchViewModel = PlaceSearchViewModel(service: GooglePlaceSearchService())

    var body: some View {
        DashMapView(viewModel: mapViewModel, location: locationStore.latestPacket)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                MapSearchView(
                    viewModel: searchViewModel,
                    destination: destinationStore.destination,
                    onClear: { destinationStore.clear() }
                )
                .frame(maxWidth: 560)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .task {
                searchViewModel.onDestinationChosen = { destinationStore.select($0) }
            }
            .onChange(of: locationStore.latestPacket) { _, packet in
                searchViewModel.origin = packet.map {
                    MapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                }
            }
            .onChange(of: destinationStore.destination) { _, destination in
                mapViewModel.setDestination(destination)
            }
    }
}

#Preview {
    let _ = GoogleMapsConfiguration.bootstrap()
    let _ = GooglePlacesConfiguration.bootstrap()
    ContentView()
        .environmentObject(LocationStore())
}
