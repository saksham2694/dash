//
//  OffRouteTests.swift
//  DashTests
//
//  M4.6 — smart off-route detection + automatic rerouting:
//    - `OffRouteDetector` — the pure classifier (on / possibly-off / confirmed-off,
//      the consecutive-fix requirement, the hysteresis band, re-signalling, and
//      re-arming on a route change);
//    - `RouteViewModel.autoReroute(...)` — current-location origin + remembered
//      destination, success / failure, no-concurrency with the manual Refresh,
//      and the post-run cooldown;
//    - `NavigationViewModel` — the detector wired into the fix stream, the
//      once-per-episode `needsAutomaticReroute` signal, and re-arming;
//    - the adopt-a-reroute sequence — destination / mode / vehicle preserved,
//      progress reset against the new route, alternatives retained.
//
//  Pure — no SDK, no networking, no real clock (`now` is injected where it
//  matters). Google → neutral mapping stays covered in `RouteTests`.
//

import Combine
import Foundation
import Testing
@testable import Dash
import DashShared

// MARK: - Fixtures

/// ~1 km of longitude at the equator.
private let kmDeg = 0.008_993

/// A straight, due-east route on the equator: origin → 1 km (depart) → 2 km
/// (continue straight) → 3 km, then a short final leg (arrive). On the equator a
/// point `m` metres north of the line projects onto it at offset ≈ `m` m.
private func straightRoute(id: String = "route") -> Route {
    let p0 = MapCoordinate(latitude: 0, longitude: 0)
    let p1 = MapCoordinate(latitude: 0, longitude: kmDeg)
    let p2 = MapCoordinate(latitude: 0, longitude: kmDeg * 2)
    let p3 = MapCoordinate(latitude: 0, longitude: kmDeg * 3)
    return Route(
        id: id,
        polyline: [p0, p1, p2, p3],
        distanceMeters: 3_000,
        duration: .seconds(300),
        steps: [
            RouteStep(maneuver: .depart, instruction: "Head east on Main St",
                      roadName: "Main St", maneuverPoint: p0, polyline: [p0, p1], distanceMeters: 1_000),
            RouteStep(maneuver: .straight, instruction: "Continue on Main St",
                      roadName: "Main St", maneuverPoint: p1, polyline: [p1, p2], distanceMeters: 1_000),
            RouteStep(maneuver: .arrive, instruction: "Arrive at destination",
                      roadName: nil, maneuverPoint: p2, polyline: [p2, p3], distanceMeters: 1_000),
        ]
    )
}

/// A coordinate `metersNorth` off the equator route, at longitude `lon`.
private func offRoad(lon: Double, metersNorth: Double) -> MapCoordinate {
    MapCoordinate(latitude: metersNorth / 111_320.0, longitude: lon)
}

private func onRoad(_ lon: Double) -> MapCoordinate {
    MapCoordinate(latitude: 0, longitude: lon)
}

private func fix(_ c: MapCoordinate) -> LocationPacket {
    LocationPacket(latitude: c.latitude, longitude: c.longitude, speed: 12, heading: 90,
                   timestamp: Date(timeIntervalSince1970: 1_756_700_000))
}

private func destination(_ id: String = "dest-1", lat: Double = 0, lon: Double = kmDeg * 3) -> Destination {
    Destination(placeID: id, name: "Somewhere", address: nil,
                coordinate: MapCoordinate(latitude: lat, longitude: lon))
}

// MARK: - OffRouteDetector

@Suite("OffRouteDetector")
struct OffRouteDetectorTests {

    private let route = straightRoute()

    @Test("a fix on the route reads on-route and never asks for a reroute")
    func onRoute() {
        var detector = OffRouteDetector()
        for lon in stride(from: 0.0, through: kmDeg * 0.9, by: kmDeg * 0.1) {
            let outcome = detector.record(position: onRoad(lon), on: route)
            #expect(outcome == .none)
            #expect(detector.status == .onRoute)
        }
    }

    @Test("a single noisy off-route fix does not trigger a reroute")
    func singleNoisyFix() {
        var detector = OffRouteDetector()
        let outcome = detector.record(position: offRoad(lon: kmDeg * 0.4, metersNorth: 250), on: route)
        #expect(outcome == .none)
        #expect(detector.status == .possiblyOffRoute)

        // Back on the route on the very next fix — episode cleared.
        let back = detector.record(position: onRoad(kmDeg * 0.42), on: route)
        #expect(back == .none)
        #expect(detector.status == .onRoute)
    }

    @Test("fewer than the confirmation count of off-route fixes stays 'possibly'")
    func belowConfirmation() {
        var detector = OffRouteDetector()
        for _ in 0..<(OffRouteDetector.confirmationFixCount - 1) {
            let outcome = detector.record(position: offRoad(lon: kmDeg * 0.5, metersNorth: 120), on: route)
            #expect(outcome == .none)
            #expect(detector.status == .possiblyOffRoute)
        }
    }

    @Test("a run of meaningful off-route fixes confirms and asks for a reroute once")
    func confirms() {
        var detector = OffRouteDetector()
        var signals = 0
        for i in 0..<OffRouteDetector.confirmationFixCount {
            let outcome = detector.record(position: offRoad(lon: kmDeg * 0.5, metersNorth: 120), on: route)
            if outcome == .requestReroute { signals += 1 }
            if i < OffRouteDetector.confirmationFixCount - 1 {
                #expect(outcome == .none)
            }
        }
        #expect(signals == 1)
        #expect(detector.status == .confirmedOffRoute)
    }

    @Test("fixes inside the hysteresis band never confirm an episode")
    func hysteresisBand() {
        var detector = OffRouteDetector()
        // Between onRouteTolerance (20 m) and offRouteThreshold (35 m).
        let ambiguous = (OffRouteDetector.onRouteToleranceMeters + OffRouteDetector.offRouteThresholdMeters) / 2
        #expect(ambiguous > OffRouteDetector.onRouteToleranceMeters)
        #expect(ambiguous < OffRouteDetector.offRouteThresholdMeters)
        for _ in 0..<20 {
            let outcome = detector.record(position: offRoad(lon: kmDeg * 0.5, metersNorth: ambiguous), on: route)
            #expect(outcome == .none)
            #expect(detector.status != .confirmedOffRoute)
        }
    }

    @Test("the refined thresholds are conservative and keep hysteresis")
    func refinedThresholds() {
        // Values chosen for the M4.6 refinement (2026-09-03): tighter than the
        // original 40 / 70 / 4 so a wrong turn is caught a road-width sooner.
        #expect(OffRouteDetector.onRouteToleranceMeters == 20)
        #expect(OffRouteDetector.offRouteThresholdMeters == 35)
        #expect(OffRouteDetector.confirmationFixCount == 3)
        // Hysteresis preserved: there is still a band between "on" and "off".
        #expect(OffRouteDetector.offRouteThresholdMeters > OffRouteDetector.onRouteToleranceMeters)
        // Never one fix (nor two).
        #expect(OffRouteDetector.confirmationFixCount >= 3)
    }

    @Test("two consecutive meaningful off-route fixes still do not trigger")
    func twoFixesDoNotTrigger() {
        var detector = OffRouteDetector()
        for _ in 0..<2 {
            #expect(detector.record(position: offRoad(lon: kmDeg * 0.5, metersNorth: 45), on: route) == .none)
        }
        #expect(detector.status == .possiblyOffRoute)
        // The third is what confirms.
        #expect(detector.record(position: offRoad(lon: kmDeg * 0.5, metersNorth: 45), on: route) == .requestReroute)
    }

    @Test("a genuine wrong turn is confirmed on the third meaningful fix, ~a road off the route")
    func respondsEarlier() {
        var detector = OffRouteDetector()
        // Just past the 35 m threshold — a parallel street, not GPS scatter.
        let outcomes = (0..<3).map { _ in
            detector.record(position: offRoad(lon: kmDeg * 0.6, metersNorth: 40), on: route)
        }
        #expect(outcomes == [.none, .none, .requestReroute])
    }

    @Test("a ~25 m drift reads as possibly-off, not on-route (tighter tolerance)")
    func tighterTolerance() {
        var detector = OffRouteDetector()
        // Inside the old 40 m tolerance, now within the hysteresis band.
        _ = detector.record(position: offRoad(lon: kmDeg * 0.5, metersNorth: 25), on: route)
        #expect(detector.status == .possiblyOffRoute)
    }

    @Test("while still off-route after signalling, it re-asks after resignalAfterFixes")
    func reSignals() {
        var detector = OffRouteDetector()
        var outcomes: [OffRouteDetector.Outcome] = []
        let total = OffRouteDetector.confirmationFixCount + OffRouteDetector.resignalAfterFixes
        for _ in 0..<total {
            outcomes.append(detector.record(position: offRoad(lon: kmDeg * 0.5, metersNorth: 150), on: route))
        }
        #expect(outcomes.filter { $0 == .requestReroute }.count == 2)
        #expect(outcomes[OffRouteDetector.confirmationFixCount - 1] == .requestReroute)
        #expect(outcomes.last == .requestReroute)
    }

    @Test("rejoining the route ends the episode; a later deviation can trigger again")
    func rejoinReArms() {
        var detector = OffRouteDetector()
        var signals = 0

        for _ in 0..<OffRouteDetector.confirmationFixCount {
            if detector.record(position: offRoad(lon: kmDeg * 0.5, metersNorth: 120), on: route) == .requestReroute {
                signals += 1
            }
        }
        // Rejoin.
        _ = detector.record(position: onRoad(kmDeg * 0.55), on: route)
        #expect(detector.status == .onRoute)

        // Deviate again.
        for _ in 0..<OffRouteDetector.confirmationFixCount {
            if detector.record(position: offRoad(lon: kmDeg * 0.7, metersNorth: 120), on: route) == .requestReroute {
                signals += 1
            }
        }
        #expect(signals == 2)
    }

    @Test("reset() re-arms detection from scratch")
    func reset() {
        var detector = OffRouteDetector()
        for _ in 0..<OffRouteDetector.confirmationFixCount {
            _ = detector.record(position: offRoad(lon: kmDeg * 0.5, metersNorth: 120), on: route)
        }
        #expect(detector.status == .confirmedOffRoute)

        detector.reset()
        #expect(detector == OffRouteDetector())
        #expect(detector.status == .onRoute)
    }

    @Test("a degenerate route polyline yields no signal")
    func degenerateRoute() {
        var detector = OffRouteDetector()
        let bare = Route(polyline: [MapCoordinate(latitude: 1, longitude: 1)], distanceMeters: 0, duration: .zero)
        #expect(detector.record(position: MapCoordinate(latitude: 2, longitude: 2), on: bare) == .none)
        #expect(detector.status == .onRoute)
    }
}

// MARK: - RouteViewModel automatic reroute

@MainActor
private final class StubRouteService: RouteService {
    var result: Result<[Route], Error> = .failure(RouteError.unavailable)
    private(set) var calls: [(origin: MapCoordinate, destination: MapCoordinate)] = []

    func routes(from origin: MapCoordinate, to destination: MapCoordinate) async throws -> [Route] {
        calls.append((origin, destination))
        return try result.get()
    }
}

private func route(_ id: String, minutes: Double = 10) -> Route {
    Route(id: id,
          polyline: [MapCoordinate(latitude: 0, longitude: 0), MapCoordinate(latitude: 0, longitude: 0.05)],
          distanceMeters: 10_000, duration: .seconds(minutes * 60))
}

@MainActor
@Suite("RouteViewModel.autoReroute")
struct RouteViewModelAutoRerouteTests {

    /// A view model that has already loaded a route for `destination()`.
    private func loaded() async -> (RouteViewModel, StubRouteService) {
        let service = StubRouteService()
        service.result = .success([route("route-0")])
        let vm = RouteViewModel(service: service)
        vm.requestRoutes(to: destination(), from: MapCoordinate(latitude: 1, longitude: 1))
        await vm.currentTask?.value
        return (vm, service)
    }

    @Test("auto reroute uses the current origin + remembered destination and offers the set")
    func usesCurrentOriginAndKeepsState() async {
        let (vm, service) = await loaded()
        let stateBefore = vm.state
        service.result = .success([route("route-0", minutes: 9), route("route-1", minutes: 11)])

        let started = vm.autoReroute(from: MapCoordinate(latitude: 9, longitude: 9))
        #expect(started)
        #expect(vm.refresh == .recalculating)
        #expect(vm.refreshWasAutomatic)
        #expect(vm.state == stateBefore)

        await vm.refreshTask?.value

        guard case .options(let options) = vm.refresh else { Issue.record("expected .options"); return }
        #expect(options.routes.count == 2)
        #expect(options.recommended.id == "route-0")
        #expect(vm.state == stateBefore)                       // active route untouched
        #expect(service.calls.last?.origin == MapCoordinate(latitude: 9, longitude: 9))
        #expect(service.calls.last?.destination == destination().coordinate)
    }

    @Test("a failed auto reroute keeps the loaded state and starts the cooldown")
    func failureKeepsStateAndArmsCooldown() async {
        let (vm, service) = await loaded()
        let stateBefore = vm.state
        service.result = .failure(RouteError.unavailable)

        #expect(vm.autoReroute(from: MapCoordinate(latitude: 2, longitude: 2)))
        await vm.refreshTask?.value

        #expect(vm.refresh == .failed(.unavailable))
        #expect(vm.state == stateBefore)
        #expect(vm.lastAutoRerouteFinishedAt != nil)
    }

    // MARK: - Loading state ("Recalculating…" pill)

    @Test("the recalculating state is exposed the instant autoReroute starts, before the request resolves")
    func loadingStateIsImmediate() async {
        let (vm, service) = await loaded()
        service.result = .success([route("route-0")])

        let started = vm.autoReroute(from: MapCoordinate(latitude: 9, longitude: 9))

        // Synchronous — the refresh Task has not run its body yet.
        #expect(started)
        #expect(vm.isRecalculating)
        #expect(vm.isAutomaticallyRecalculating)
        #expect(vm.refresh == .recalculating)

        await vm.refreshTask?.value
        // Request resolved → no longer "recalculating".
        #expect(vm.isRecalculating == false)
        #expect(vm.isAutomaticallyRecalculating == false)
    }

    @Test("starting an automatic reroute publishes a change SwiftUI can observe")
    func autoRerouteIsObservable() async {
        let (vm, service) = await loaded()
        service.result = .success([route("route-0")])

        var published = 0
        let cancellable = vm.objectWillChange.sink { _ in published += 1 }
        defer { cancellable.cancel() }

        vm.autoReroute(from: MapCoordinate(latitude: 2, longitude: 2))
        #expect(published >= 1)                 // objectWillChange fired synchronously
    }

    @Test("a manual refresh's recalculating state is not flagged automatic")
    func manualRecalculatingIsNotAutomatic() async {
        let (vm, service) = await loaded()
        service.result = .success([route("route-0")])

        vm.refreshRoutes(from: MapCoordinate(latitude: 2, longitude: 2))
        #expect(vm.isRecalculating)
        #expect(vm.isAutomaticallyRecalculating == false)   // manual → no auto pill
        await vm.refreshTask?.value
    }

    @Test("a failed automatic reroute drops the loading state and keeps the automatic flag for the failure copy")
    func failureDropsLoadingStateKeepsFlag() async {
        let (vm, service) = await loaded()
        service.result = .failure(RouteError.unavailable)

        vm.autoReroute(from: MapCoordinate(latitude: 2, longitude: 2))
        #expect(vm.isAutomaticallyRecalculating)            // shown immediately
        await vm.refreshTask?.value

        #expect(vm.isAutomaticallyRecalculating == false)   // loading pill gone
        #expect(vm.refresh == .failed(.unavailable))
        #expect(vm.refreshWasAutomatic)                     // drives "Couldn't recalculate…" copy
    }

    @Test("adopting the reroute (clearRefresh) ends the loading state")
    func clearRefreshEndsLoadingState() async {
        let (vm, service) = await loaded()
        service.result = .success([route("route-0")])
        vm.autoReroute(from: MapCoordinate(latitude: 2, longitude: 2))
        await vm.refreshTask?.value

        vm.clearRefresh()
        #expect(vm.isRecalculating == false)
        #expect(vm.isAutomaticallyRecalculating == false)
        #expect(vm.refreshWasAutomatic == false)
    }

    @Test("no remembered destination → no request")
    func needsDestination() {
        let service = StubRouteService()
        let vm = RouteViewModel(service: service)
        #expect(vm.autoReroute(from: MapCoordinate(latitude: 1, longitude: 1)) == false)
        #expect(service.calls.isEmpty)
        #expect(vm.refresh == .none)
    }

    @Test("no current fix → no request, and nothing shown (the detector re-asks later)")
    func needsOrigin() async {
        let (vm, service) = await loaded()
        let callsBefore = service.calls.count
        #expect(vm.autoReroute(from: nil) == false)
        #expect(service.calls.count == callsBefore)
        #expect(vm.refresh == .none)
    }

    @Test("a second auto reroute is refused while one is in flight")
    func noConcurrentAutoReroutes() async {
        let (vm, service) = await loaded()
        service.result = .success([route("route-0")])
        let callsBefore = service.calls.count

        let first = vm.autoReroute(from: MapCoordinate(latitude: 2, longitude: 2))
        let second = vm.autoReroute(from: MapCoordinate(latitude: 3, longitude: 3))
        #expect(first)
        #expect(second == false)

        await vm.refreshTask?.value
        #expect(service.calls.count == callsBefore + 1)
    }

    @Test("auto reroute is refused while a manual refresh is running")
    func blockedByManualRefresh() async {
        let (vm, service) = await loaded()
        service.result = .success([route("route-0"), route("route-1")])

        vm.refreshRoutes(from: MapCoordinate(latitude: 2, longitude: 2)) // manual, now .recalculating
        #expect(vm.refresh == .recalculating)
        #expect(vm.autoReroute(from: MapCoordinate(latitude: 3, longitude: 3)) == false)

        await vm.refreshTask?.value
        #expect(vm.refreshWasAutomatic == false)                // still the manual run
    }

    @Test("a manual refresh interrupts an in-flight auto reroute without a stale result")
    func manualRefreshWins() async {
        let (vm, service) = await loaded()
        service.result = .success([route("route-0")])

        #expect(vm.autoReroute(from: MapCoordinate(latitude: 2, longitude: 2)))
        let autoTask = vm.refreshTask

        vm.refreshRoutes(from: MapCoordinate(latitude: 5, longitude: 5))
        #expect(autoTask?.isCancelled == true)

        await vm.refreshTask?.value
        guard case .options = vm.refresh else { Issue.record("expected .options"); return }
        #expect(vm.refreshWasAutomatic == false)                // the manual run stands
        #expect(service.calls.contains { $0.origin == MapCoordinate(latitude: 5, longitude: 5) })
    }

    @Test("the cooldown blocks a second auto reroute until it elapses")
    func cooldown() async {
        let (vm, service) = await loaded()
        service.result = .success([route("route-0")])
        #expect(vm.autoReroute(from: MapCoordinate(latitude: 2, longitude: 2)))
        await vm.refreshTask?.value
        vm.clearRefresh()

        let finished = try! #require(vm.lastAutoRerouteFinishedAt)
        #expect(vm.canAutoReroute(now: finished.addingTimeInterval(5)) == false)
        #expect(vm.autoReroute(from: MapCoordinate(latitude: 3, longitude: 3),
                               now: finished.addingTimeInterval(5)) == false)
        #expect(vm.canAutoReroute(now: finished.addingTimeInterval(RouteViewModel.autoRerouteCooldownSeconds + 1)))
    }

    @Test("a manual refresh is never blocked by the auto-reroute cooldown")
    func manualRefreshIgnoresCooldown() async {
        let (vm, service) = await loaded()
        service.result = .success([route("route-0")])
        #expect(vm.autoReroute(from: MapCoordinate(latitude: 2, longitude: 2)))
        await vm.refreshTask?.value
        vm.clearRefresh()

        vm.refreshRoutes(from: MapCoordinate(latitude: 3, longitude: 3))
        #expect(vm.refresh == .recalculating)
        #expect(vm.refreshWasAutomatic == false)
    }

    @Test("choosing a new destination clears the cooldown")
    func newDestinationClearsCooldown() async {
        let (vm, service) = await loaded()
        service.result = .success([route("route-0")])
        #expect(vm.autoReroute(from: MapCoordinate(latitude: 2, longitude: 2)))
        await vm.refreshTask?.value
        #expect(vm.lastAutoRerouteFinishedAt != nil)

        vm.requestRoutes(to: destination("other"), from: MapCoordinate(latitude: 1, longitude: 1))
        #expect(vm.lastAutoRerouteFinishedAt == nil)
        await vm.currentTask?.value
        #expect(vm.canAutoReroute())
    }

    @Test("clearRefresh resets the automatic flag")
    func clearRefreshResetsFlag() async {
        let (vm, service) = await loaded()
        service.result = .success([route("route-0")])
        #expect(vm.autoReroute(from: MapCoordinate(latitude: 2, longitude: 2)))
        await vm.refreshTask?.value

        vm.clearRefresh()
        #expect(vm.refresh == .none)
        #expect(vm.refreshWasAutomatic == false)
    }
}

// MARK: - NavigationViewModel off-route detection

@MainActor
@Suite("NavigationViewModel off-route")
struct NavigationViewModelOffRouteTests {

    private func navigating() -> NavigationViewModel {
        let vm = NavigationViewModel()
        vm.start(route: straightRoute(), from: MapCoordinate(latitude: 0, longitude: 0))
        return vm
    }

    @Test("staying on the route never asks for a reroute")
    func onRouteStaysQuiet() {
        let vm = navigating()
        for lon in stride(from: 0.0, through: kmDeg * 0.8, by: kmDeg * 0.1) {
            vm.update(with: onRoad(lon))
            #expect(vm.offRouteStatus == .onRoute)
            #expect(vm.needsAutomaticReroute == false)
        }
    }

    @Test("one wild fix does not ask for a reroute")
    func oneWildFix() {
        let vm = navigating()
        vm.update(with: offRoad(lon: kmDeg * 0.3, metersNorth: 400))
        #expect(vm.needsAutomaticReroute == false)
        vm.update(with: onRoad(kmDeg * 0.32))
        #expect(vm.offRouteStatus == .onRoute)
    }

    @Test("a sustained deviation confirms and raises needsAutomaticReroute once")
    func sustainedDeviation() {
        let vm = navigating()
        for _ in 0..<(OffRouteDetector.confirmationFixCount + 1) {
            vm.update(with: offRoad(lon: kmDeg * 0.4, metersNorth: 160))
        }
        #expect(vm.offRouteStatus == .confirmedOffRoute)
        #expect(vm.needsAutomaticReroute)

        vm.clearRerouteRequest()
        #expect(vm.needsAutomaticReroute == false)

        // Back on route — stands down.
        vm.update(with: onRoad(kmDeg * 0.45))
        #expect(vm.offRouteStatus == .onRoute)
    }

    @Test("reroute() re-arms detection against the new route")
    func rerouteReArms() {
        let vm = navigating()
        for _ in 0..<(OffRouteDetector.confirmationFixCount + 1) {
            vm.update(with: offRoad(lon: kmDeg * 0.4, metersNorth: 160))
        }
        #expect(vm.needsAutomaticReroute)

        // A new route the vehicle IS on (shifted north so the old fixes are on it).
        let shifted = Route(
            id: "route-1",
            polyline: [offRoad(lon: 0, metersNorth: 160),
                       offRoad(lon: kmDeg, metersNorth: 160),
                       offRoad(lon: kmDeg * 2, metersNorth: 160)],
            distanceMeters: 2_000, duration: .seconds(200),
            steps: [
                RouteStep(maneuver: .depart, instruction: "Go", roadName: "Alt",
                          maneuverPoint: offRoad(lon: 0, metersNorth: 160),
                          polyline: [offRoad(lon: 0, metersNorth: 160), offRoad(lon: kmDeg, metersNorth: 160)],
                          distanceMeters: 1_000),
                RouteStep(maneuver: .arrive, instruction: "Arrive", roadName: nil,
                          maneuverPoint: offRoad(lon: kmDeg, metersNorth: 160),
                          polyline: [offRoad(lon: kmDeg, metersNorth: 160), offRoad(lon: kmDeg * 2, metersNorth: 160)],
                          distanceMeters: 1_000),
            ]
        )
        vm.reroute(to: shifted, from: offRoad(lon: kmDeg * 0.4, metersNorth: 160))

        #expect(vm.needsAutomaticReroute == false)
        #expect(vm.offRouteStatus == .onRoute)
        #expect(vm.isActive)

        vm.update(with: offRoad(lon: kmDeg * 0.5, metersNorth: 160))
        #expect(vm.offRouteStatus == .onRoute)                 // now on the adopted route
    }

    @Test("stop() clears the off-route state")
    func stopClears() {
        let vm = navigating()
        for _ in 0..<(OffRouteDetector.confirmationFixCount + 1) {
            vm.update(with: offRoad(lon: kmDeg * 0.4, metersNorth: 160))
        }
        #expect(vm.needsAutomaticReroute)

        vm.stop()
        #expect(vm.needsAutomaticReroute == false)
        #expect(vm.offRouteStatus == .onRoute)
    }

    @Test("updates while inactive do not touch the off-route state")
    func inactiveIsInert() {
        let vm = NavigationViewModel()
        vm.update(with: offRoad(lon: kmDeg * 0.4, metersNorth: 400))
        #expect(vm.offRouteStatus == .onRoute)
        #expect(vm.needsAutomaticReroute == false)
    }
}

// MARK: - Adopting an automatic reroute (MapViewModel + NavigationViewModel)

@MainActor
@Suite("Automatic reroute adoption")
struct AutomaticRerouteAdoptionTests {

    /// The exact call sequence `MapFullScreenView.adoptAutomaticReroute` runs.
    private func adopt(_ options: RouteOptions,
                       map: MapViewModel,
                       nav: NavigationViewModel,
                       origin: MapCoordinate) {
        nav.reroute(to: options.recommended, from: origin)
        map.setRouteOptions(options)
        map.selectRouteOption(options.recommended.id)
        map.setNavigationProgress(nav.progress)
    }

    private func startedSession() -> (MapViewModel, NavigationViewModel, Destination) {
        let map = MapViewModel()
        let nav = NavigationViewModel()
        let dest = destination()
        map.update(with: fix(onRoad(0)))
        map.setDestination(dest)
        map.setRoute(straightRoute(id: "route-0"))
        map.startNavigation()
        nav.start(route: straightRoute(id: "route-0"), from: onRoad(0))
        // advance a little
        map.update(with: fix(onRoad(kmDeg * 0.5)))
        nav.update(with: onRoad(kmDeg * 0.5))
        map.setNavigationProgress(nav.progress)
        return (map, nav, dest)
    }

    @Test("adopting the recommended route keeps the session, destination and vehicle")
    func preservesSessionContext() {
        let (map, nav, dest) = startedSession()
        let vehicleBefore = map.content.vehicle.coordinate

        let options = RouteOptions([straightRoute(id: "route-1"), straightRoute(id: "route-2")])!
        adopt(options, map: map, nav: nav, origin: onRoad(kmDeg * 0.5))

        #expect(map.mode == .navigating)                       // session not restarted
        #expect(nav.isActive)
        #expect(map.destination == dest)                       // destination preserved
        #expect(map.content.vehicle.coordinate == vehicleBefore) // indicator preserved
        #expect(map.route?.id == "route-1")                    // recommended adopted
        #expect(nav.route?.id == "route-1")
    }

    @Test("progress is reset and re-seeded against the new route")
    func resetsProgress() {
        let (map, nav) = { let s = startedSession(); return (s.0, s.1) }()
        // A bogus large progress that must not survive adoption.
        map.setNavigationProgress(NavigationProgress(stepIndex: 2, distanceToManeuverMeters: 5,
                                                     distanceRemainingMeters: 5, traveledMeters: 9_999,
                                                     isArrived: false))

        let options = RouteOptions([straightRoute(id: "route-1")])!
        adopt(options, map: map, nav: nav, origin: onRoad(kmDeg * 0.5))

        let progress = try! #require(nav.progress)
        #expect(progress.traveledMeters < 9_999)               // recomputed, not carried over
        #expect(map.navigationProgress == nav.progress)        // mirrored
    }

    @Test("the returned alternatives stay available in the route-options architecture")
    func keepsAlternatives() {
        let (map, nav, _) = startedSession()
        let options = RouteOptions([straightRoute(id: "route-1"), straightRoute(id: "route-2")])!
        adopt(options, map: map, nav: nav, origin: onRoad(kmDeg * 0.5))

        #expect(map.routeOptions?.routes.map(\.id) == ["route-1", "route-2"])
        #expect(map.routeOptions?.selected.id == "route-1")
        let byRole = Dictionary(grouping: map.content.polylines, by: \.role)
        #expect(byRole[.selected]?.map(\.id) == ["route-1"])
        #expect(byRole[.alternative]?.map(\.id) == ["route-2"])
        #expect(map.content.polylines.contains { $0.id == "route-0" } == false) // old geometry gone
    }
}
