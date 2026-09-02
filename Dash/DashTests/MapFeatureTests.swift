//
//  MapFeatureTests.swift
//  DashTests
//
//  `MapFeature` — manifest, and (M5.1) app-scoped ownership of the Map runtime
//  state: presenting the Map screen must observe the feature's view models, not
//  build fresh ones, so an active route / navigation session survives leaving
//  and re-entering Maps.
//

import Foundation
import SwiftUI
import Testing
@testable import Dash
import DashShared

@MainActor
@Suite("MapFeature")
struct MapFeatureTests {

    @Test("manifest is well-formed and stable")
    func manifest() {
        let manifest = MapFeature().manifest

        #expect(manifest.id == "maps")
        #expect(manifest.id == MapFeature.id)
        #expect(!manifest.title.isEmpty)
        #expect(!manifest.symbolName.isEmpty)
        #expect(manifest.supportedSizes.contains(manifest.defaultSize))
        #expect(manifest.supportedWidgetSizes == [.compact, .medium, .large])
    }

    @Test("owns its view models — the same instances for the feature's lifetime")
    func stableOwnership() {
        let feature = MapFeature()

        let map = feature.mapViewModel
        let destinations = feature.destinationStore
        let search = feature.searchViewModel
        let route = feature.routeViewModel
        let nav = feature.navigationViewModel

        // Asking for the full-screen view any number of times must not swap the
        // owned state.
        _ = feature.makeFullScreenView()
        _ = feature.makeFullScreenView()

        #expect(feature.mapViewModel === map)
        #expect(feature.destinationStore === destinations)
        #expect(feature.searchViewModel === search)
        #expect(feature.routeViewModel === route)
        #expect(feature.navigationViewModel === nav)
    }

    @Test("presenting the Map screen observes the feature's instances, not new ones")
    func viewObservesFeatureState() {
        let feature = MapFeature()

        let first = MapFullScreenView(feature: feature)
        let second = MapFullScreenView(feature: feature)

        // Each presentation binds to the feature's objects…
        #expect(first.mapViewModel === feature.mapViewModel)
        #expect(first.destinationStore === feature.destinationStore)
        #expect(first.searchViewModel === feature.searchViewModel)
        #expect(first.routeViewModel === feature.routeViewModel)
        #expect(first.navigationViewModel === feature.navigationViewModel)

        // …so two presentations share the exact same runtime state.
        #expect(first.mapViewModel === second.mapViewModel)
        #expect(first.routeViewModel === second.routeViewModel)
        #expect(first.navigationViewModel === second.navigationViewModel)
    }

    @Test("an active navigation session is not recreated by re-presenting Maps")
    func navigationSurvivesRePresentation() {
        let feature = MapFeature()
        let map = feature.mapViewModel
        let nav = feature.navigationViewModel

        let origin = MapCoordinate(latitude: 12.9600, longitude: 77.6400)
        let mid = MapCoordinate(latitude: 12.9700, longitude: 77.6500)
        let end = MapCoordinate(latitude: 12.9800, longitude: 77.6600)

        let fix = LocationPacket(
            latitude: origin.latitude, longitude: origin.longitude,
            speed: 8, heading: 90,
            timestamp: Date(timeIntervalSince1970: 1_756_700_000)
        )
        let destination = Destination(
            placeID: "dst", name: "Somewhere", address: nil, coordinate: end
        )
        let route = Route(
            id: "route-0",
            polyline: [origin, mid, end],
            distanceMeters: 2_800,
            duration: .seconds(360),
            steps: [
                RouteStep(maneuver: .depart, instruction: "Head north", roadName: "A St",
                          maneuverPoint: origin, polyline: [origin, mid], distanceMeters: 1_400),
                RouteStep(maneuver: .arrive, instruction: "Arrive", roadName: nil,
                          maneuverPoint: end, polyline: [mid, end], distanceMeters: 1_400),
            ]
        )

        // Stand up a route + navigation session, the way the full-screen view's
        // Start action does.
        map.update(with: fix)
        map.setDestination(destination)
        map.setRoute(route)
        map.startNavigation()
        nav.start(route: route, from: origin)

        #expect(map.mode == .navigating)
        #expect(nav.isActive)

        // Simulate Maps → Home → Maps: the old view is gone, a new one is built.
        _ = MapFullScreenView(feature: feature)

        // The session is still the same live objects, still navigating.
        #expect(feature.mapViewModel === map)
        #expect(feature.navigationViewModel === nav)
        #expect(feature.mapViewModel.mode == .navigating)
        #expect(feature.navigationViewModel.isActive)
        #expect(feature.mapViewModel.route?.id == "route-0")
    }

    @Test("view models are injectable for tests")
    func injectableViewModels() {
        let map = MapViewModel()
        let nav = NavigationViewModel()
        let feature = MapFeature(mapViewModel: map, navigationViewModel: nav)

        #expect(feature.mapViewModel === map)
        #expect(feature.navigationViewModel === nav)
    }

    @Test("picking a search suggestion routes into the feature's DestinationStore")
    func searchWiringPersists() {
        let feature = MapFeature()
        let destination = Destination(
            placeID: "p1", name: "Test", address: nil,
            coordinate: MapCoordinate(latitude: 1, longitude: 2)
        )

        feature.searchViewModel.onDestinationChosen(destination)

        #expect(feature.destinationStore.destination == destination)
    }
}
