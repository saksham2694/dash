//
//  MapComponentTests.swift
//  DashTests
//
//  M5.2.1 — the real Map dashboard components. Covers the pure presentation
//  decision + widget camera, that the components observe the app-scoped
//  `MapFeature` view models (never new ones), and that `MapFeature.dashboardObserve`
//  keeps a live navigation session current while deduping multi-widget pumps.
//

import Foundation
import SwiftUI
import Testing
@testable import Dash
import DashShared

// MARK: - Fixtures

private func steppedRoute(id: String = "route-0") -> Route {
    let a = MapCoordinate(latitude: 12.9600, longitude: 77.6400)
    let b = MapCoordinate(latitude: 12.9700, longitude: 77.6500)
    let c = MapCoordinate(latitude: 12.9800, longitude: 77.6600)
    return Route(
        id: id,
        polyline: [a, b, c],
        distanceMeters: 2_800,
        duration: .seconds(360),
        steps: [
            RouteStep(maneuver: .depart, instruction: "Head north", roadName: "A St",
                      maneuverPoint: a, polyline: [a, b], distanceMeters: 1_400),
            RouteStep(maneuver: .arrive, instruction: "Arrive", roadName: nil,
                      maneuverPoint: c, polyline: [b, c], distanceMeters: 1_400),
        ]
    )
}

private func packet(
    _ lat: Double = 12.9600, _ lon: Double = 77.6400,
    heading: Double = 0, at t: TimeInterval = 1_756_700_000
) -> LocationPacket {
    LocationPacket(latitude: lat, longitude: lon, speed: 8, heading: heading,
                   timestamp: Date(timeIntervalSince1970: t))
}

private func destination() -> Destination {
    Destination(placeID: "d1", name: "Somewhere", address: nil,
                coordinate: MapCoordinate(latitude: 12.9800, longitude: 77.6600))
}

@MainActor
private func navigatingFeature() -> MapFeature {
    let feature = MapFeature()
    let route = steppedRoute()
    let origin = MapCoordinate(latitude: 12.9600, longitude: 77.6400)

    feature.mapViewModel.update(with: packet())
    feature.mapViewModel.setDestination(destination())
    feature.mapViewModel.setRoute(route)
    feature.mapViewModel.startNavigation()
    feature.navigationViewModel.start(route: route, from: origin)
    return feature
}

// MARK: - Presentation decision (pure)

@Suite("MapComponentPresenter")
struct MapComponentPresenterTests {

    @Test("large / medium / full always show a live map")
    func mapSizes() {
        for size in [ComponentSize.large, .medium, .full] {
            #expect(MapComponentPresenter.presentation(size: size, navigating: false, hasDestination: false) == .liveMap)
            #expect(MapComponentPresenter.presentation(size: size, navigating: true, hasDestination: true) == .liveMap)
        }
    }

    @Test("compact prefers the maneuver glance while navigating")
    func compactNavigating() {
        #expect(MapComponentPresenter.presentation(size: .compact, navigating: true, hasDestination: false) == .maneuverGlance)
        #expect(MapComponentPresenter.presentation(size: .compact, navigating: true, hasDestination: true) == .maneuverGlance)
    }

    @Test("compact shows the destination summary, then idle, when not navigating")
    func compactIdleAndDestination() {
        #expect(MapComponentPresenter.presentation(size: .compact, navigating: false, hasDestination: true) == .destinationSummary)
        #expect(MapComponentPresenter.presentation(size: .compact, navigating: false, hasDestination: false) == .idle)
    }
}

// MARK: - Widget camera (pure)

@Suite("MapDashboardCamera")
struct MapDashboardCameraTests {

    private let vehicle = MapCoordinate(latitude: 1, longitude: 2)

    @Test("cruising is north-up at the wide zoom")
    func cruising() {
        let plan = MapDashboardCamera.plan(style: .cruising, vehicle: vehicle, heading: 90)
        #expect(plan == .follow(MapCameraState(
            latitude: 1, longitude: 2, headingDegrees: nil, zoom: MapDashboardCamera.cruisingZoom
        )))
    }

    @Test("navigating is heading-up at the road-level zoom")
    func navigating() {
        let plan = MapDashboardCamera.plan(style: .navigating, vehicle: vehicle, heading: 90)
        #expect(plan == .follow(MapCameraState(
            latitude: 1, longitude: 2, headingDegrees: 90, zoom: MapDashboardCamera.navigatingZoom
        )))
    }

    @Test("an invalid heading keeps the navigating camera north-up")
    func invalidHeading() {
        let plan = MapDashboardCamera.plan(style: .navigating, vehicle: vehicle, heading: -1)
        #expect(plan == .follow(MapCameraState(
            latitude: 1, longitude: 2, headingDegrees: nil, zoom: MapDashboardCamera.navigatingZoom
        )))
    }
}

// MARK: - MapComponentView / MapFeature

@MainActor
@Suite("Map dashboard components")
struct MapComponentViewTests {

    @Test("MapFeature vends a real component per widget size, not the M5.2.0 placeholder")
    func realComponents() {
        let feature = MapFeature()

        #expect(MapComponentView(feature: feature, size: .large).presentation == .liveMap)
        #expect(MapComponentView(feature: feature, size: .medium).presentation == .liveMap)
        #expect(MapComponentView(feature: feature, size: .compact).presentation == .idle)

        // Vended without creating new runtime state.
        let nav = feature.navigationViewModel
        _ = feature.makeComponentView(size: .large)
        _ = feature.makeComponentView(size: .compact)
        #expect(feature.navigationViewModel === nav)
    }

    @Test("compact chooses maneuver guidance over a map while navigating")
    func compactNavigating() {
        let feature = navigatingFeature()
        #expect(MapComponentView(feature: feature, size: .compact).presentation == .maneuverGlance)
    }

    @Test("compact shows the destination summary once a destination is set")
    func compactDestination() {
        let feature = MapFeature()
        feature.destinationStore.select(destination())
        #expect(MapComponentView(feature: feature, size: .compact).presentation == .destinationSummary)
    }

    @Test("medium and large stay live maps regardless of navigation state")
    func mediumLargeStayMaps() {
        let idle = MapFeature()
        #expect(MapComponentView(feature: idle, size: .medium).presentation == .liveMap)
        #expect(MapComponentView(feature: idle, size: .large).presentation == .liveMap)

        let navigating = navigatingFeature()
        #expect(MapComponentView(feature: navigating, size: .medium).presentation == .liveMap)
        #expect(MapComponentView(feature: navigating, size: .large).presentation == .liveMap)
    }

    @Test("every component observes the feature's own view models")
    func componentsObserveSharedState() {
        let feature = MapFeature()

        let large = MapLargeComponent(feature: feature)
        let medium = MapMediumComponent(feature: feature)
        let compact = MapCompactComponent(feature: feature)

        #expect(large.mapViewModel === feature.mapViewModel)
        #expect(large.navigationViewModel === feature.navigationViewModel)
        #expect(medium.mapViewModel === feature.mapViewModel)
        #expect(medium.destinationStore === feature.destinationStore)
        #expect(compact.navigationViewModel === feature.navigationViewModel)
        #expect(compact.mapViewModel === feature.mapViewModel)

        // …and therefore each other's.
        #expect(large.mapViewModel === medium.mapViewModel)
        #expect(large.mapViewModel === compact.mapViewModel)
        #expect(medium.navigationViewModel === compact.navigationViewModel)
    }

    @Test("mounting several components creates no additional Map runtime state")
    func noExtraRuntimeState() {
        let feature = MapFeature()
        let map = feature.mapViewModel
        let nav = feature.navigationViewModel
        let dest = feature.destinationStore
        let route = feature.routeViewModel
        let search = feature.searchViewModel

        _ = MapLargeComponent(feature: feature)
        _ = MapMediumComponent(feature: feature)
        _ = MapCompactComponent(feature: feature)
        _ = feature.makeComponentView(size: .large)
        _ = feature.makeComponentView(size: .medium)
        _ = feature.makeComponentView(size: .compact)

        #expect(feature.mapViewModel === map)
        #expect(feature.navigationViewModel === nav)
        #expect(feature.destinationStore === dest)
        #expect(feature.routeViewModel === route)
        #expect(feature.searchViewModel === search)
    }
}

// MARK: - dashboardObserve

@MainActor
@Suite("MapFeature.dashboardObserve")
struct MapFeatureDashboardObserveTests {

    @Test("a fix moves the shared vehicle indicator and records the timestamp")
    func pumpsSharedState() {
        let feature = MapFeature()
        feature.dashboardObserve(packet(12.9611, 77.6422, at: 500))

        #expect(feature.lastObservedDashboardFix == Date(timeIntervalSince1970: 500))
        #expect(feature.mapViewModel.content.vehicle.coordinate
                == MapCoordinate(latitude: 12.9611, longitude: 77.6422))
    }

    @Test("a repeated fix (same timestamp) is a no-op")
    func dedupesByTimestamp() {
        let feature = navigatingFeature()

        // Two distinct off-route fixes, each fed twice — with dedup only two
        // *meaningful* off-route fixes reach the detector, one short of
        // `confirmationFixCount` (3).
        for t in [600.0, 601.0] {
            let p = packet(12.9000, 77.6400, at: t)
            feature.dashboardObserve(p)
            feature.dashboardObserve(p)
        }
        #expect(feature.navigationViewModel.offRouteStatus != .confirmedOffRoute)

        // A third distinct off-route fix confirms it.
        feature.dashboardObserve(packet(12.9000, 77.6400, at: 602))
        #expect(feature.navigationViewModel.offRouteStatus == .confirmedOffRoute)
    }

    @Test("advances the live navigation session while the dashboard is on screen")
    func advancesNavigation() {
        let feature = navigatingFeature()
        let before = feature.navigationViewModel.progress

        // A fix ~80% along the first step.
        feature.dashboardObserve(packet(12.9680, 77.6480, at: 700))

        let after = feature.navigationViewModel.progress
        #expect(before != nil && after != nil)
        #expect((after?.traveledMeters ?? 0) > (before?.traveledMeters ?? 0))
    }

    @Test("does nothing to a session that isn't navigating")
    func inertWhenNotNavigating() {
        let feature = MapFeature()
        feature.dashboardObserve(packet(at: 800))
        #expect(feature.navigationViewModel.isActive == false)
        #expect(feature.navigationViewModel.progress == nil)
    }
}
