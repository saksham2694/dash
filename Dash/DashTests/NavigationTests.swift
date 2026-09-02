//
//  NavigationTests.swift
//  DashTests
//
//  M4.3 turn-by-turn: geodesic helpers, the navigation progress engine, the
//  navigation view model, the maneuver card model, and the navigation camera /
//  dynamic zoom on `MapViewModel`. No SDK, no networking — the Google → neutral
//  maneuver mapping is covered in `RouteTests`.
//

import Foundation
import Testing
@testable import Dash
import DashShared

// MARK: - Shared fixtures

/// ~1000 m of longitude at the equator.
private let oneKmDegrees = 0.008_993

/// An L-shaped route: east ~1 km (depart), north ~1 km (turn left), east ~0.5 km
/// (turn right), then a short final leg to the destination (arrive). Step
/// distances are left at 0 so the engine measures them from the geometry and
/// stays self-consistent.
private func lRoute() -> Route {
    let p0 = MapCoordinate(latitude: 0, longitude: 0)
    let p1 = MapCoordinate(latitude: 0, longitude: oneKmDegrees)
    let p2 = MapCoordinate(latitude: oneKmDegrees, longitude: oneKmDegrees)
    let p3 = MapCoordinate(latitude: oneKmDegrees, longitude: oneKmDegrees * 1.5)
    let p4 = MapCoordinate(latitude: oneKmDegrees, longitude: oneKmDegrees * 1.53) // ~33 m final leg

    return Route(
        polyline: [p0, p1, p2, p3, p4],
        distanceMeters: 2530,
        duration: .seconds(300),
        steps: [
            RouteStep(maneuver: .depart, instruction: "Head east on First St",
                      roadName: "First St", maneuverPoint: p0, polyline: [p0, p1], distanceMeters: 0),
            RouteStep(maneuver: .turnLeft, instruction: "Turn left onto North Rd",
                      roadName: "North Rd", maneuverPoint: p1, polyline: [p1, p2], distanceMeters: 0),
            RouteStep(maneuver: .turnRight, instruction: "Turn right onto East Ave",
                      roadName: "East Ave", maneuverPoint: p2, polyline: [p2, p3], distanceMeters: 0),
            RouteStep(maneuver: .arrive, instruction: "Arrive at destination",
                      roadName: nil, maneuverPoint: p3, polyline: [p3, p4], distanceMeters: 0),
        ]
    )
}

/// A point `fraction` of the way along `[a, b]`.
private func lerp(_ a: MapCoordinate, _ b: MapCoordinate, _ fraction: Double) -> MapCoordinate {
    MapCoordinate(
        latitude: a.latitude + (b.latitude - a.latitude) * fraction,
        longitude: a.longitude + (b.longitude - a.longitude) * fraction
    )
}

// MARK: - Geodesic helpers

@Suite("RouteGeometry")
struct RouteGeometryTests {

    @Test("haversine distance is right for a short east/west span")
    func haversine() {
        let d = RouteGeometry.distance(
            MapCoordinate(latitude: 0, longitude: 0),
            MapCoordinate(latitude: 0, longitude: oneKmDegrees)
        )
        #expect(abs(d - 1000) < 5)
    }

    @Test("polyline length sums its segments")
    func length() {
        let line = [
            MapCoordinate(latitude: 0, longitude: 0),
            MapCoordinate(latitude: 0, longitude: oneKmDegrees),
            MapCoordinate(latitude: oneKmDegrees, longitude: oneKmDegrees),
        ]
        #expect(abs(RouteGeometry.length(line) - 2000) < 10)
    }

    @Test("projecting a point onto a polyline finds the closest point and distance along")
    func projection() {
        let line = [
            MapCoordinate(latitude: 0, longitude: 0),
            MapCoordinate(latitude: 0, longitude: oneKmDegrees),
        ]
        // A point beside the middle of the segment, offset ~1 km north.
        let p = MapCoordinate(latitude: oneKmDegrees, longitude: oneKmDegrees / 2)
        let projection = try! #require(RouteGeometry.project(p, onto: line))
        #expect(projection.segmentIndex == 0)
        #expect(abs(projection.distanceAlong - 500) < 10)
        #expect(abs(projection.distanceFromInput - 1000) < 10)
    }

    @Test("projection clamps to the polyline ends")
    func projectionClamps() {
        let line = [
            MapCoordinate(latitude: 0, longitude: 0),
            MapCoordinate(latitude: 0, longitude: oneKmDegrees),
        ]
        let before = MapCoordinate(latitude: 0, longitude: -oneKmDegrees)
        let projection = try! #require(RouteGeometry.project(before, onto: line))
        #expect(projection.distanceAlong == 0)
    }

    // MARK: remainingPolyline (M4.4)

    private var straightLine: [MapCoordinate] {
        [MapCoordinate(latitude: 0, longitude: 0),
         MapCoordinate(latitude: 0, longitude: oneKmDegrees),      // 1 km
         MapCoordinate(latitude: 0, longitude: oneKmDegrees * 2),  // 2 km
         MapCoordinate(latitude: 0, longitude: oneKmDegrees * 3)]  // 3 km
    }

    @Test("at the start, the remaining polyline is essentially the whole route")
    func remainingAtStart() {
        let remaining = RouteGeometry.remainingPolyline(of: straightLine, from: straightLine[0])
        #expect(abs(RouteGeometry.length(remaining) - 3000) < 20)
        #expect(remaining.last == straightLine.last)
    }

    @Test("mid-route, the remaining polyline starts at the vehicle and ends at the destination")
    func remainingMidRoute() {
        // ~1.5 km along, a touch off the line.
        let here = MapCoordinate(latitude: 0.000_02, longitude: oneKmDegrees * 1.5)
        let remaining = RouteGeometry.remainingPolyline(of: straightLine, from: here)

        #expect(remaining.count >= 2)
        #expect(remaining.last == straightLine.last)
        #expect(abs(RouteGeometry.length(remaining) - 1500) < 30)      // ~half left
        #expect(RouteGeometry.distance(remaining[0], here) < 10)       // starts under the vehicle
        // The already-travelled first vertex is gone.
        #expect(!remaining.contains(straightLine[0]))
    }

    @Test("the remaining polyline only ever shrinks as the vehicle advances")
    func remainingMonotonicallyShrinks() {
        var previous = Double.greatestFiniteMagnitude
        for fraction in stride(from: 0.0, through: 1.0, by: 0.2) {
            let here = MapCoordinate(latitude: 0, longitude: oneKmDegrees * 3 * fraction)
            let length = RouteGeometry.length(
                RouteGeometry.remainingPolyline(of: straightLine, from: here)
            )
            #expect(length <= previous + 1)
            previous = length
        }
    }

    @Test("past the end, nothing is left to draw")
    func remainingPastEnd() {
        let beyond = MapCoordinate(latitude: 0, longitude: oneKmDegrees * 4)
        #expect(RouteGeometry.remainingPolyline(of: straightLine, from: beyond).isEmpty)
    }

    @Test("a degenerate polyline is returned untouched")
    func remainingDegenerate() {
        let single = [MapCoordinate(latitude: 1, longitude: 1)]
        #expect(RouteGeometry.remainingPolyline(of: single, from: single[0]) == single)
        #expect(RouteGeometry.remainingPolyline(of: [], from: single[0]).isEmpty)
    }
}

// MARK: - Progress engine

@Suite("NavigationProgressCalculator")
struct NavigationProgressTests {

    private let route = lRoute()

    @Test("initial progress points at the first turn and reports the distance to it")
    func initialProgress() {
        let p = NavigationProgressCalculator.initial(for: route, at: route.steps[0].maneuverPoint)
        #expect(p.stepIndex == 1)                       // the turn-left step
        #expect(abs(p.distanceToManeuverMeters - 1000) < 20)
        #expect(abs(p.distanceRemainingMeters - 2530) < 40)
        #expect(p.isArrived == false)
    }

    @Test("distance to the maneuver shrinks as the vehicle moves along the step")
    func distanceToManeuverShrinks() {
        var p = NavigationProgressCalculator.initial(for: route, at: route.steps[0].maneuverPoint)
        let quarter = lerp(route.steps[0].polyline[0], route.steps[0].polyline[1], 0.25)
        let threeQuarter = lerp(route.steps[0].polyline[0], route.steps[0].polyline[1], 0.75)

        p = NavigationProgressCalculator.next(p, route: route, position: quarter)
        let atQuarter = p.distanceToManeuverMeters
        p = NavigationProgressCalculator.next(p, route: route, position: threeQuarter)
        let atThreeQuarter = p.distanceToManeuverMeters

        #expect(atQuarter > atThreeQuarter)
        #expect(abs(atQuarter - 750) < 30)
        #expect(abs(atThreeQuarter - 250) < 30)
        #expect(p.stepIndex == 1)                       // still approaching the first turn
    }

    @Test("passing a maneuver advances to the next one")
    func advancesPastManeuver() {
        var p = NavigationProgressCalculator.initial(for: route, at: route.steps[0].maneuverPoint)
        // A little way onto step 1 (past the turn-left point).
        let ontoStep1 = lerp(route.steps[1].polyline[0], route.steps[1].polyline[1], 0.1)
        p = NavigationProgressCalculator.next(p, route: route, position: ontoStep1)

        #expect(p.stepIndex == 2)                       // now approaching the turn-right
        #expect(p.distanceToManeuverMeters > 700)       // most of step 1 still ahead
    }

    @Test("one noisy fix that jumps far ahead never skips more than one maneuver")
    func noisyFixDoesNotSkipManeuvers() {
        var p = NavigationProgressCalculator.initial(for: route, at: route.steps[0].maneuverPoint)
        #expect(p.stepIndex == 1)

        // A fix that lands (on-route) near the very end of the route — two
        // maneuvers beyond where we are.
        let farAhead = lerp(route.steps[2].polyline[0], route.steps[2].polyline[1], 0.5)
        p = NavigationProgressCalculator.next(p, route: route, position: farAhead)

        #expect(p.stepIndex == 2) // advanced by exactly one, not to 3
    }

    @Test("a fix far off the route is ignored and progress is unchanged")
    func offRouteFixIgnored() {
        var p = NavigationProgressCalculator.initial(for: route, at: route.steps[0].maneuverPoint)
        let quarter = lerp(route.steps[0].polyline[0], route.steps[0].polyline[1], 0.25)
        p = NavigationProgressCalculator.next(p, route: route, position: quarter)
        let before = p

        // ~2 km north of anything on the route.
        let wildFix = MapCoordinate(latitude: oneKmDegrees * 2, longitude: quarter.longitude)
        p = NavigationProgressCalculator.next(p, route: route, position: wildFix)

        #expect(p == before)
    }

    @Test("progress never moves backward on a fix that projects earlier")
    func progressIsMonotonic() {
        var p = NavigationProgressCalculator.initial(for: route, at: route.steps[0].maneuverPoint)
        let half = lerp(route.steps[0].polyline[0], route.steps[0].polyline[1], 0.5)
        p = NavigationProgressCalculator.next(p, route: route, position: half)
        let midTravel = p.traveledMeters

        let back = lerp(route.steps[0].polyline[0], route.steps[0].polyline[1], 0.2)
        p = NavigationProgressCalculator.next(p, route: route, position: back)
        #expect(p.traveledMeters >= midTravel)
    }

    @Test("reaching the destination flips isArrived")
    func arrival() {
        var p = NavigationProgressCalculator.initial(for: route, at: route.steps[0].maneuverPoint)
        // Walk the whole route in ~120 m hops so nothing is skipped.
        let full = route.polyline
        for i in 0..<(full.count - 1) {
            for f in stride(from: 0.0, through: 1.0, by: 0.1) {
                p = NavigationProgressCalculator.next(p, route: route, position: lerp(full[i], full[i + 1], f))
            }
        }
        #expect(p.isArrived)
        #expect(p.distanceRemainingMeters < NavigationProgressCalculator.arrivalRadiusMeters)
    }

    @Test("a route with no steps yields a benign inactive-style progress")
    func noSteps() {
        let bare = Route(polyline: [MapCoordinate(latitude: 0, longitude: 0),
                                    MapCoordinate(latitude: 1, longitude: 1)],
                         distanceMeters: 100, duration: .zero)
        let p = NavigationProgressCalculator.initial(for: bare, at: MapCoordinate(latitude: 0, longitude: 0))
        #expect(p.stepIndex == 0)
        #expect(p.isArrived == false)
    }
}

// MARK: - Navigation view model

@MainActor
@Suite("NavigationViewModel")
struct NavigationViewModelTests {

    private func route() -> Route { lRoute() }

    @Test("starts inactive with no card")
    func startsInactive() {
        let vm = NavigationViewModel()
        #expect(vm.state == .inactive)
        #expect(vm.isActive == false)
        #expect(vm.maneuverCard == nil)
        #expect(vm.progress == nil)
    }

    @Test("start with a route and an origin begins navigating and builds a maneuver card")
    func startsNavigating() {
        let vm = NavigationViewModel()
        vm.start(route: route(), from: route().steps[0].maneuverPoint)

        #expect(vm.isActive)
        let card = try! #require(vm.maneuverCard)
        #expect(card.primaryText == "Turn left")
        #expect(card.detailText == "North Rd")
        #expect(card.distanceText != nil)
        #expect(card.isArrival == false)
    }

    @Test("start without an origin stays inactive")
    func startNeedsOrigin() {
        let vm = NavigationViewModel()
        vm.start(route: route(), from: nil)
        #expect(vm.state == .inactive)
    }

    @Test("start with a step-less route stays inactive")
    func startNeedsSteps() {
        let vm = NavigationViewModel()
        vm.start(route: Route(polyline: [MapCoordinate(latitude: 0, longitude: 0),
                                         MapCoordinate(latitude: 1, longitude: 1)],
                              distanceMeters: 1, duration: .zero),
                 from: MapCoordinate(latitude: 0, longitude: 0))
        #expect(vm.state == .inactive)
    }

    @Test("updates advance the card to the next maneuver")
    func updateAdvancesCard() {
        let r = route()
        let vm = NavigationViewModel()
        vm.start(route: r, from: r.steps[0].maneuverPoint)

        vm.update(with: lerp(r.steps[1].polyline[0], r.steps[1].polyline[1], 0.1))
        let card = try! #require(vm.maneuverCard)
        #expect(card.primaryText == "Turn right")
        #expect(card.detailText == "East Ave")
    }

    @Test("reaching the destination shows the arrival card")
    func arrivalCard() {
        let r = route()
        let vm = NavigationViewModel()
        vm.start(route: r, from: r.steps[0].maneuverPoint)
        for i in 0..<(r.polyline.count - 1) {
            for f in stride(from: 0.0, through: 1.0, by: 0.1) {
                vm.update(with: lerp(r.polyline[i], r.polyline[i + 1], f))
            }
        }
        #expect(vm.state == .arrived)
        #expect(vm.maneuverCard == .arrived)
    }

    @Test("stop returns to inactive and drops the route")
    func stops() {
        let r = route()
        let vm = NavigationViewModel()
        vm.start(route: r, from: r.steps[0].maneuverPoint)
        vm.stop()
        #expect(vm.state == .inactive)
        #expect(vm.route == nil)
        #expect(vm.maneuverCard == nil)
    }

    @Test("updates are ignored while inactive")
    func inactiveIgnoresUpdates() {
        let vm = NavigationViewModel()
        vm.update(with: MapCoordinate(latitude: 1, longitude: 1))
        #expect(vm.state == .inactive)
    }

    // MARK: reroute (M4.5)

    @Test("reroute swaps the route and re-seeds progress without leaving navigation")
    func reroutes() {
        let old = route()
        let vm = NavigationViewModel()
        vm.start(route: old, from: old.steps[0].maneuverPoint)
        // advance a little so progress is non-initial
        vm.update(with: lerp(old.steps[0].polyline[0], old.steps[0].polyline[1], 0.5))

        // A different route to the same place.
        let new = Route(
            id: "route-1",
            polyline: [old.steps[0].maneuverPoint, old.polyline.last!],
            distanceMeters: 1_000, duration: .seconds(120),
            steps: [
                RouteStep(maneuver: .depart, instruction: "Head off", roadName: "New Rd",
                          maneuverPoint: old.steps[0].maneuverPoint,
                          polyline: [old.steps[0].maneuverPoint, old.polyline.last!],
                          distanceMeters: 0),
                RouteStep(maneuver: .arrive, instruction: "Arrive", roadName: nil,
                          maneuverPoint: old.polyline.last!,
                          polyline: [old.polyline.last!,
                                     MapCoordinate(latitude: old.polyline.last!.latitude + 0.0003,
                                                   longitude: old.polyline.last!.longitude)],
                          distanceMeters: 0),
            ]
        )

        vm.reroute(to: new, from: old.steps[0].maneuverPoint)

        #expect(vm.isActive)                    // session kept
        #expect(vm.route?.id == "route-1")
        // progress re-seeded from the start of the new route
        #expect(vm.progress?.traveledMeters == 0)
        #expect(vm.progress?.stepIndex == 1)    // approaching the new route's arrive step
    }

    @Test("reroute is a no-op when not navigating")
    func rerouteInactive() {
        let vm = NavigationViewModel()
        vm.reroute(to: route(), from: MapCoordinate(latitude: 0, longitude: 0))
        #expect(vm.state == .inactive)
    }

    @Test("reroute is a no-op without an origin")
    func rerouteNeedsOrigin() {
        let r = route()
        let vm = NavigationViewModel()
        vm.start(route: r, from: r.steps[0].maneuverPoint)
        vm.reroute(to: route(), from: nil)
        #expect(vm.route?.id == "route") // unchanged
    }
}

// MARK: - Maneuver card model

@Suite("ManeuverCard / NavigationDistance")
struct ManeuverCardModelTests {

    @Test("distance formatting rounds sensibly by band")
    func distanceFormatting() {
        #expect(NavigationDistance.text(forMeters: 8) == "Now")
        #expect(NavigationDistance.text(forMeters: 47) == "50 m")
        #expect(NavigationDistance.text(forMeters: 220) == "220 m")
        #expect(NavigationDistance.text(forMeters: 640) == "650 m")
        #expect(NavigationDistance.text(forMeters: 1420) == "1.4 km")
        #expect(NavigationDistance.text(forMeters: -5) == "Now")
    }

    @Test("maneuver types carry a phrase and an arrow, or fall back to raw text")
    func maneuverPresentation() {
        #expect(ManeuverType.turnRight.phrase == "Turn right")
        #expect(ManeuverType.turnRight.symbolName == "arrow.turn.up.right")
        #expect(ManeuverType.unknown.phrase == nil)

        let step = RouteStep(maneuver: .unknown, instruction: "Bear onto the slip road",
                             maneuverPoint: MapCoordinate(latitude: 0, longitude: 0),
                             polyline: [MapCoordinate(latitude: 0, longitude: 0),
                                        MapCoordinate(latitude: 0, longitude: 1)],
                             distanceMeters: 100)
        #expect(step.primaryText == "Bear onto the slip road")
    }

    @Test("only genuine changes of road warrant a closer camera view")
    func closerViewClassification() {
        #expect(ManeuverType.turnLeft.warrantsCloserView)
        #expect(ManeuverType.roundabout.warrantsCloserView)
        #expect(ManeuverType.straight.warrantsCloserView == false)
        #expect(ManeuverType.merge.warrantsCloserView == false)
        #expect(ManeuverType.arrive.warrantsCloserView == false)
    }
}

// MARK: - Navigation camera & dynamic zoom (MapViewModel)

@MainActor
@Suite("MapViewModel navigation camera")
struct NavigationCameraTests {

    private func fix(_ lat: Double, _ lon: Double, heading: Double = 90) -> LocationPacket {
        LocationPacket(latitude: lat, longitude: lon, speed: 12, heading: heading,
                       timestamp: Date(timeIntervalSince1970: 1_756_700_000))
    }

    private func previewedRoute(_ vm: MapViewModel) -> Route {
        let route = lRoute()
        vm.update(with: fix(0, 0))
        vm.setDestination(Destination(placeID: "d", name: "Dest", address: nil,
                                      coordinate: route.polyline.last!))
        vm.setRoute(route)
        return route
    }

    @Test("cannot start navigation without a route, a fix, and preview mode")
    func startNavigationGuard() {
        let vm = MapViewModel()
        #expect(vm.canStartNavigation == false)

        vm.update(with: fix(0, 0))
        vm.setDestination(Destination(placeID: "d", name: "X", address: nil,
                                      coordinate: MapCoordinate(latitude: 1, longitude: 1)))
        #expect(vm.canStartNavigation == false) // still no route

        vm.setRoute(lRoute())
        #expect(vm.canStartNavigation)

        vm.startNavigation()
        #expect(vm.mode == .navigating)
        #expect(vm.followsVehicle)
        #expect(vm.canStartNavigation == false) // no longer previewing
    }

    @Test("startNavigation is a no-op with no fix")
    func startNavigationNeedsFix() {
        let vm = MapViewModel()
        vm.setDestination(Destination(placeID: "d", name: "X", address: nil,
                                      coordinate: MapCoordinate(latitude: 1, longitude: 1)))
        vm.setRoute(lRoute())
        vm.startNavigation()
        #expect(vm.mode == .destinationPreview)
    }

    @Test("the navigation camera plan tilts and anchors the vehicle a little below centre")
    func navigationCameraShape() {
        let vm = MapViewModel()
        _ = previewedRoute(vm)
        vm.startNavigation()

        guard case .navigation(_, let pitch, let anchor) = vm.content.camera else {
            Issue.record("expected a .navigation camera plan")
            return
        }
        #expect(pitch == MapViewModel.navigationPitchDegrees)
        #expect(anchor == MapViewModel.navigationVehicleAnchor)
        #expect(anchor > 0.5) // below centre
        #expect(anchor < 0.7) // not pushed excessively
    }

    @Test("with no progress the navigation zoom is the base zoom")
    func zoomWithoutProgress() {
        let vm = MapViewModel()
        _ = previewedRoute(vm)
        vm.startNavigation()

        guard case .navigation(let state, _, _) = vm.content.camera else {
            Issue.record("expected a .navigation camera plan"); return
        }
        #expect(state.zoom == MapViewModel.navigationBaseZoom)
    }

    @Test("nearing a significant maneuver zooms in; clearing it eases back to base")
    func dynamicZoom() {
        let vm = MapViewModel()
        let route = previewedRoute(vm)
        vm.startNavigation()

        // Approaching the first turn (turnLeft, significant), 120 m out.
        vm.setNavigationProgress(NavigationProgress(
            stepIndex: 1, distanceToManeuverMeters: 120, distanceRemainingMeters: 1500,
            traveledMeters: 900, isArrived: false
        ))
        guard case .navigation(let close, _, _) = vm.content.camera else {
            Issue.record("expected a .navigation camera plan"); return
        }
        #expect(close.zoom > MapViewModel.navigationBaseZoom)

        // Far from the next maneuver again → back to base.
        vm.setNavigationProgress(NavigationProgress(
            stepIndex: 2, distanceToManeuverMeters: 900, distanceRemainingMeters: 900,
            traveledMeters: 1100, isArrived: false
        ))
        guard case .navigation(let farState, _, _) = vm.content.camera else {
            Issue.record("expected a .navigation camera plan"); return
        }
        #expect(farState.zoom == MapViewModel.navigationBaseZoom)

        _ = route
    }

    @Test("a non-significant upcoming maneuver does not trigger a zoom-in")
    func noZoomForStraight() {
        #expect(MapViewModel.navigationZoom(
            base: 16, distanceToManeuverMeters: 60, approachingSignificantManeuver: false
        ) == 16)
        #expect(MapViewModel.navigationZoom(
            base: 16, distanceToManeuverMeters: 60, approachingSignificantManeuver: true
        ) > 16)
        #expect(MapViewModel.navigationZoom(
            base: 16, distanceToManeuverMeters: 5000, approachingSignificantManeuver: true
        ) == 16)
    }

    @Test("the dynamic zoom is quantised so it changes in discrete steps")
    func zoomQuantised() {
        let zooms = stride(from: 350.0, through: 40.0, by: -5.0).map {
            MapViewModel.navigationZoom(base: 16, distanceToManeuverMeters: $0,
                                        approachingSignificantManeuver: true)
        }
        for z in zooms {
            #expect((z * 2).rounded() / 2 == z) // lands on a 0.5 grid
        }
        #expect(Set(zooms).count <= 5) // only a handful of distinct values
    }

    @Test("with follow off, navigation progress does not move or zoom the camera")
    func followOffFreezesCamera() {
        let vm = MapViewModel()
        _ = previewedRoute(vm)
        vm.startNavigation()
        vm.handle(.cameraIdle(
            MapCameraPosition(center: MapCoordinate(latitude: 5, longitude: 5), zoom: 14, headingDegrees: 0),
            byUserGesture: true
        ))
        #expect(vm.followsVehicle == false)
        let frozen = vm.content.camera

        vm.setNavigationProgress(NavigationProgress(
            stepIndex: 1, distanceToManeuverMeters: 80, distanceRemainingMeters: 1000,
            traveledMeters: 950, isArrived: false
        ))
        #expect(vm.content.camera == frozen)
    }

    @Test("recenter restores navigation follow with the navigation plan")
    func recenterRestoresNavigationFollow() {
        let vm = MapViewModel()
        _ = previewedRoute(vm)
        vm.startNavigation()
        vm.setNavigationProgress(NavigationProgress(
            stepIndex: 1, distanceToManeuverMeters: 100, distanceRemainingMeters: 1000,
            traveledMeters: 900, isArrived: false
        ))
        vm.handle(.cameraIdle(
            MapCameraPosition(center: MapCoordinate(latitude: 5, longitude: 5), zoom: 14, headingDegrees: 0),
            byUserGesture: true
        ))
        #expect(vm.followsVehicle == false)

        vm.recenter()
        #expect(vm.followsVehicle)
        guard case .navigation(let state, _, _) = vm.content.camera else {
            Issue.record("expected a .navigation camera plan"); return
        }
        #expect(state.zoom > MapViewModel.navigationBaseZoom) // dynamic zoom still applied
    }

    @Test("leaving navigation clears the progress and the dynamic zoom")
    func leavingNavigationClearsProgress() {
        let vm = MapViewModel()
        _ = previewedRoute(vm)
        vm.startNavigation()
        vm.setNavigationProgress(NavigationProgress(
            stepIndex: 1, distanceToManeuverMeters: 80, distanceRemainingMeters: 900,
            traveledMeters: 950, isArrived: false
        ))

        vm.setDestination(nil)
        #expect(vm.mode == .cruising)
        #expect(vm.navigationProgress == nil)
        #expect(vm.content.camera == .follow(vm.camera))
    }
}

// MARK: - Progressive route shortening (MapViewModel, M4.4)

@MainActor
@Suite("MapViewModel route rendering")
struct RemainingRouteRenderTests {

    private func fix(_ c: MapCoordinate) -> LocationPacket {
        LocationPacket(latitude: c.latitude, longitude: c.longitude, speed: 12,
                       heading: 90, timestamp: Date(timeIntervalSince1970: 1_756_700_000))
    }

    private func drawn(_ vm: MapViewModel) -> [MapCoordinate] {
        vm.content.polylines.first?.coordinates ?? []
    }

    private func previewed(_ vm: MapViewModel) -> Route {
        let route = lRoute()
        vm.update(with: fix(route.polyline[0]))
        vm.setDestination(Destination(placeID: "d", name: "Dest", address: nil,
                                      coordinate: route.polyline.last!))
        vm.setRoute(route)
        return route
    }

    @Test("the full route is drawn while previewing")
    func fullRouteInPreview() {
        let vm = MapViewModel()
        let route = previewed(vm)
        #expect(drawn(vm) == route.polyline)
    }

    @Test("a later fix while previewing does not shorten the drawn route")
    func previewNotShortenedByFixes() {
        let vm = MapViewModel()
        let route = previewed(vm)
        vm.update(with: fix(route.polyline[2])) // "moved", but still previewing
        #expect(drawn(vm) == route.polyline)
    }

    @Test("during navigation the drawn route is only the part still ahead of the vehicle")
    func navigationShortensRoute() {
        let vm = MapViewModel()
        let route = previewed(vm)
        vm.startNavigation()
        let full = RouteGeometry.length(route.polyline)

        vm.update(with: fix(route.polyline[2])) // ~2 km along a ~2.5 km route

        let remaining = drawn(vm)
        #expect(remaining.count >= 2)
        #expect(remaining.last == route.polyline.last)          // still ends at the destination
        #expect(!remaining.contains(route.polyline[0]))         // the travelled start is gone
        #expect(RouteGeometry.length(remaining) < full - 1_000) // meaningfully shorter
    }

    @Test("advancing further shortens the drawn route further")
    func routeKeepsShrinking() {
        let vm = MapViewModel()
        let route = previewed(vm)
        vm.startNavigation()

        vm.update(with: fix(route.polyline[1]))
        let early = RouteGeometry.length(drawn(vm))
        vm.update(with: fix(route.polyline[3]))
        let late = RouteGeometry.length(drawn(vm))

        #expect(late < early)
    }

    @Test("arriving at the destination leaves no stale route geometry")
    func arrivalClearsRoute() {
        let vm = MapViewModel()
        let route = previewed(vm)
        vm.startNavigation()
        vm.update(with: fix(route.polyline.last!))
        #expect(vm.content.polylines.isEmpty)
    }

    @Test("ending navigation (clearing the destination) removes the route line")
    func endNavigationClearsRoute() {
        let vm = MapViewModel()
        _ = previewed(vm)
        vm.startNavigation()
        vm.update(with: fix(lRoute().polyline[1]))
        #expect(vm.content.polylines.isEmpty == false)

        vm.setDestination(nil)
        #expect(vm.content.polylines.isEmpty)
    }

    @Test("the original Route is never mutated by rendering")
    func routeModelUntouched() {
        let vm = MapViewModel()
        let route = previewed(vm)
        vm.startNavigation()
        vm.update(with: fix(route.polyline[2]))
        #expect(vm.route?.polyline == route.polyline) // full geometry retained
    }
}
