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
//  the search view model, the destination store, the routing view model, and the
//  navigation view model, and wires them together. None of those know about each
//  other.
//

import DashShared
import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var locationStore: LocationStore

    @StateObject private var mapViewModel = MapViewModel()
    @StateObject private var destinationStore = DestinationStore()
    @StateObject private var searchViewModel = PlaceSearchViewModel(service: GooglePlaceSearchService())
    @StateObject private var routeViewModel = RouteViewModel(service: GoogleRouteService())
    @StateObject private var navigationViewModel = NavigationViewModel()

    /// Latest usable vehicle position, or `nil` before the first fix. Routing,
    /// navigation progress, and search bias all read this from `LocationStore` —
    /// no feature touches GPS itself.
    private var currentOrigin: MapCoordinate? {
        locationStore.latestPacket.map {
            MapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var isNavigating: Bool {
        mapViewModel.mode == .navigating
    }

    var body: some View {
        DashMapView(viewModel: mapViewModel, location: locationStore.latestPacket)
            .ignoresSafeArea()
            .overlay(alignment: .top) { topOverlay }
            .overlay(alignment: .bottom) {
                if mapViewModel.canStartNavigation {
                    StartNavigationButton { startNavigation() }
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: mapViewModel.canStartNavigation)
            .animation(.easeInOut(duration: 0.2), value: isNavigating)
            .task {
                searchViewModel.onDestinationChosen = { destinationStore.select($0) }
            }
            .onChange(of: locationStore.latestPacket) { _, packet in
                let coordinate = packet.map {
                    MapCoordinate(latitude: $0.latitude, longitude: $0.longitude)
                }
                searchViewModel.origin = coordinate
                navigationViewModel.update(with: coordinate)
                mapViewModel.setNavigationProgress(navigationViewModel.progress)
            }
            .onChange(of: destinationStore.destination) { _, destination in
                navigationViewModel.stop()
                mapViewModel.setDestination(destination)
                routeViewModel.requestRoute(to: destination, from: currentOrigin)
            }
            .onChange(of: routeViewModel.state) { _, state in
                if case .loaded(let route) = state {
                    mapViewModel.setRoute(route)
                } else {
                    mapViewModel.setRoute(nil)
                }
            }
            .onChange(of: navigationViewModel.state) { _, _ in
                mapViewModel.setNavigationProgress(navigationViewModel.progress)
            }
    }

    @ViewBuilder
    private var topOverlay: some View {
        if isNavigating, let card = navigationViewModel.maneuverCard {
            ManeuverCardView(card: card) { endNavigation() }
                .frame(maxWidth: 560)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
        } else if !isNavigating {
            VStack(spacing: 0) {
                MapSearchView(
                    viewModel: searchViewModel,
                    destination: destinationStore.destination,
                    onClear: { destinationStore.clear() }
                )
                RouteStatusView(
                    viewModel: routeViewModel,
                    onRetry: {
                        routeViewModel.requestRoute(to: destinationStore.destination, from: currentOrigin)
                    }
                )
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    /// Begin turn-by-turn from the loaded route + current location.
    private func startNavigation() {
        guard case .loaded(let route) = routeViewModel.state else { return }
        mapViewModel.startNavigation()
        navigationViewModel.start(route: route, from: currentOrigin)
        mapViewModel.setNavigationProgress(navigationViewModel.progress)
    }

    /// Leave navigation. Clearing the destination cascades back to cruising via
    /// the `onChange(of: destinationStore.destination)` handler.
    private func endNavigation() {
        navigationViewModel.stop()
        destinationStore.clear()
    }
}

#Preview {
    let _ = GoogleMapsConfiguration.bootstrap()
    let _ = GooglePlacesConfiguration.bootstrap()
    ContentView()
        .environmentObject(LocationStore())
}
