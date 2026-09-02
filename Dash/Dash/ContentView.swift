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

    private var isRefreshingRoute: Bool {
        routeViewModel.refresh == .recalculating
    }

    /// A freshly recalculated set of routes awaiting the driver's choice (M4.5).
    private var refreshedOptions: RouteOptions? {
        if case .options(let options) = routeViewModel.refresh { return options }
        return nil
    }

    /// Short status line for a refresh that couldn't run / failed.
    private var refreshStatusText: String? {
        switch routeViewModel.refresh {
        case .noCurrentLocation: return "Can't refresh — waiting for GPS"
        case .failed: return "Couldn't refresh the route"
        default: return nil
        }
    }

    var body: some View {
        DashMapView(viewModel: mapViewModel, location: locationStore.latestPacket)
            .ignoresSafeArea()
            .overlay(alignment: .top) { topOverlay }
            .overlay(alignment: .bottom) { bottomOverlay }
            .animation(.easeInOut(duration: 0.2), value: mapViewModel.canStartNavigation)
            .animation(.easeInOut(duration: 0.2), value: isNavigating)
            .animation(.easeInOut(duration: 0.2), value: mapViewModel.route)
            .animation(.easeInOut(duration: 0.2), value: routeViewModel.refresh)
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
                routeViewModel.requestRoutes(to: destination, from: currentOrigin)
            }
            .onChange(of: routeViewModel.state) { _, state in
                if case .loaded(let options) = state {
                    mapViewModel.setRouteOptions(options)
                } else {
                    mapViewModel.setRouteOptions(nil)
                }
            }
            .onChange(of: routeViewModel.refresh) { _, refresh in
                // Draw a freshly recalculated set as selectable alternatives —
                // in navigation this leaves the active route alone (M4.5).
                if case .options(let options) = refresh {
                    mapViewModel.setRouteOptions(options)
                }
            }
            .onChange(of: navigationViewModel.state) { _, _ in
                mapViewModel.setNavigationProgress(navigationViewModel.progress)
            }
    }

    // MARK: - Bottom overlay

    /// Route options / info panel(s) / Start button. `TimelineView` keeps the
    /// ETA current without a hand-rolled timer.
    private var bottomOverlay: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 12) {
                // A mid-navigation refresh result — pick a route or keep current.
                if isNavigating, let options = refreshedOptions {
                    RouteOptionsPanelView(
                        summaries: options.summaries,
                        onSelect: { adoptRefreshedRoute($0) },
                        onDismiss: { dismissRefresh() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Destination preview: option selector (2+ routes) + info + Start.
                if mapViewModel.mode == .destinationPreview, let route = mapViewModel.route {
                    if let options = mapViewModel.routeOptions, options.hasAlternatives {
                        RouteOptionsPanelView(
                            summaries: options.summaries,
                            onSelect: { mapViewModel.selectRouteOption($0) }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
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

                // Live navigation figures.
                if let info = navigationViewModel.routeInfo(now: context.date) {
                    RouteInfoPanelView(info: info)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Top overlay

    @ViewBuilder
    private var topOverlay: some View {
        if isNavigating {
            VStack(spacing: 8) {
                if let card = navigationViewModel.maneuverCard {
                    ManeuverCardView(
                        card: card,
                        onEnd: { endNavigation() },
                        onRefresh: refreshedOptions == nil ? { refreshRoute() } : nil,
                        isRefreshing: isRefreshingRoute
                    )
                }
                if let text = refreshStatusText {
                    refreshStatusPill(text)
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            VStack(spacing: 0) {
                MapSearchView(
                    viewModel: searchViewModel,
                    destination: destinationStore.destination,
                    onClear: { destinationStore.clear() }
                )
                RouteStatusView(
                    viewModel: routeViewModel,
                    onRetry: {
                        routeViewModel.requestRoutes(to: destinationStore.destination, from: currentOrigin)
                    }
                )
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private func refreshStatusPill(_ text: String) -> some View {
        Button {
            routeViewModel.clearRefresh()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text(text)
            }
            .font(.subheadline)
            .foregroundStyle(Color(uiColor: .label))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Dismiss")
    }

    // MARK: - Actions

    /// Begin turn-by-turn from the selected route + current location.
    private func startNavigation() {
        guard let route = mapViewModel.route else { return }
        mapViewModel.startNavigation()
        navigationViewModel.start(route: route, from: currentOrigin)
        mapViewModel.setNavigationProgress(navigationViewModel.progress)
    }

    /// Leave navigation. Clearing the destination cascades back to cruising via
    /// the `onChange(of: destinationStore.destination)` handler.
    private func endNavigation() {
        navigationViewModel.stop()
        routeViewModel.clearRefresh()
        destinationStore.clear()
    }

    /// Manually recalculate routes from the current location (M4.5).
    private func refreshRoute() {
        routeViewModel.refreshRoutes(from: currentOrigin)
    }

    /// The driver picked one of the recalculated routes — adopt it without
    /// tearing down the session.
    private func adoptRefreshedRoute(_ id: String) {
        guard case .options(let options) = routeViewModel.refresh,
              let route = options.routes.first(where: { $0.id == id }) else { return }
        navigationViewModel.reroute(to: route, from: currentOrigin)
        mapViewModel.selectRouteOption(id)
        mapViewModel.setNavigationProgress(navigationViewModel.progress)
        routeViewModel.clearRefresh()
    }

    /// The driver dismissed the recalculated routes — keep the current one.
    private func dismissRefresh() {
        routeViewModel.clearRefresh()
        mapViewModel.setRouteOptions(nil)
    }
}

#Preview {
    let _ = GoogleMapsConfiguration.bootstrap()
    let _ = GooglePlacesConfiguration.bootstrap()
    ContentView()
        .environmentObject(LocationStore())
}
