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

    /// The route currently loaded for the chosen destination, if any.
    private var loadedRoute: Route? {
        if case .loaded(let route) = routeViewModel.state { return route }
        return nil
    }

    var body: some View {
        DashMapView(viewModel: mapViewModel, location: locationStore.latestPacket)
            .ignoresSafeArea()
            .overlay(alignment: .top) { topOverlay }
            .overlay(alignment: .bottom) { bottomOverlay }
            .animation(.easeInOut(duration: 0.2), value: mapViewModel.canStartNavigation)
            .animation(.easeInOut(duration: 0.2), value: isNavigating)
            .animation(.easeInOut(duration: 0.2), value: loadedRoute)
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

    /// The route-info panel(s) and the Start Navigation button. `TimelineView`
    /// keeps the ETA current without a hand-rolled timer; during navigation the
    /// panel also refreshes on each GPS fix (`navigationViewModel.state` changes).
    ///
    /// In destination preview the info panel and the Start button share one
    /// bottom row (panel flexible + larger, button hugging its content on the
    /// right); during navigation the live panel is on its own, full width.
    private var bottomOverlay: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 12) {
                if mapViewModel.mode == .destinationPreview, let route = loadedRoute {
                    HStack(spacing: 12) {
                        RouteInfoPanelView(info: .preview(route: route, now: context.date))
                            .frame(maxWidth: .infinity)
                        if mapViewModel.canStartNavigation {
                            StartNavigationButton { startNavigation() }
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let info = navigationViewModel.routeInfo(now: context.date) {
                    RouteInfoPanelView(info: info)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
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
