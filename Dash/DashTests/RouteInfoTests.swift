//
//  RouteInfoTests.swift
//  DashTests
//
//  M4.4 route info & ETA: distance / duration / clock formatting, the remaining-
//  duration derivation off `NavigationProgress`, the `RouteInfo` builders for the
//  preview and live panels, and `NavigationViewModel.routeInfo(now:)`. Pure — no
//  SDK, no networking, no real clock (ETA is computed from an injected `now`).
//

import Foundation
import Testing
@testable import Dash
import DashShared

// MARK: - Fixtures

private func route(distanceMeters: Double = 10_000, duration: Duration = .seconds(600)) -> Route {
    Route(
        polyline: [MapCoordinate(latitude: 0, longitude: 0),
                   MapCoordinate(latitude: 0, longitude: 0.05)],
        distanceMeters: distanceMeters,
        duration: duration
    )
}

private func progress(remaining: Double, arrived: Bool = false) -> NavigationProgress {
    NavigationProgress(
        stepIndex: 1,
        distanceToManeuverMeters: min(remaining, 200),
        distanceRemainingMeters: remaining,
        traveledMeters: max(0, 10_000 - remaining),
        isArrived: arrived
    )
}

/// A concrete instant, from a calendar pinned to `timeZone`.
private func instant(hour: Int, minute: Int, timeZone: TimeZone) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: hour, minute: minute))!
}

private let newYork = TimeZone(identifier: "America/New_York")!
private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
private let usEnglish = Locale(identifier: "en_US")
private let ukEnglish = Locale(identifier: "en_GB")

// MARK: - Formatting

@Suite("RouteFormat")
struct RouteFormatTests {

    @Test("distance rounds by band and switches to km")
    func distance() {
        #expect(RouteFormat.distance(meters: 0) == "0 m")
        #expect(RouteFormat.distance(meters: -50) == "0 m")
        #expect(RouteFormat.distance(meters: 47) == "50 m")
        #expect(RouteFormat.distance(meters: 130) == "150 m")
        #expect(RouteFormat.distance(meters: 1_400) == "1.4 km")
        #expect(RouteFormat.distance(meters: 12_000) == "12 km")
        #expect(RouteFormat.distance(meters: 23_600) == "24 km")
    }

    @Test("duration rounds to minutes, then hours + minutes")
    func duration() {
        #expect(RouteFormat.duration(.seconds(0)) == "< 1 min")
        #expect(RouteFormat.duration(.seconds(20)) == "< 1 min")
        #expect(RouteFormat.duration(.seconds(-100)) == "< 1 min")
        #expect(RouteFormat.duration(.seconds(45)) == "1 min")
        #expect(RouteFormat.duration(.seconds(90)) == "2 min")
        #expect(RouteFormat.duration(.seconds(600)) == "10 min")
        #expect(RouteFormat.duration(.seconds(3_600)) == "1 hr")
        #expect(RouteFormat.duration(.seconds(4_500)) == "1 hr 15 min")
        #expect(RouteFormat.duration(.seconds(7_200)) == "2 hr")
    }

    @Test("clock time follows the given locale")
    func timeLocale() {
        let noon = instant(hour: 15, minute: 45, timeZone: newYork)
        let us = RouteFormat.time(noon, locale: usEnglish, timeZone: newYork)
        let uk = RouteFormat.time(noon, locale: ukEnglish, timeZone: newYork)

        #expect(us != uk)
        #expect(us.contains("3:45"))
        #expect(us.uppercased().contains("PM"))
        #expect(uk.contains("15:45"))
    }

    @Test("clock time follows the given time zone")
    func timeZoneShift() {
        let sameInstant = instant(hour: 15, minute: 45, timeZone: newYork)
        let east = RouteFormat.time(sameInstant, locale: ukEnglish, timeZone: newYork)
        let west = RouteFormat.time(sameInstant, locale: ukEnglish, timeZone: losAngeles)

        #expect(east == "15:45")
        #expect(west == "12:45") // 3 hours behind
    }
}

@Suite("Duration.inSeconds")
struct DurationInSecondsTests {

    @Test("converts whole and fractional durations")
    func converts() {
        #expect(Duration.seconds(90).inSeconds == 90)
        #expect(Duration.zero.inSeconds == 0)
        #expect(abs(Duration.milliseconds(1_500).inSeconds - 1.5) < 1e-9)
        #expect(abs(Duration.seconds(3.5).inSeconds - 3.5) < 1e-9)
    }
}

// MARK: - Remaining duration derivation

@Suite("NavigationProgress.remainingDuration")
struct RemainingDurationTests {

    @Test("scales the route duration by the fraction of distance left")
    func scales() {
        let r = route(distanceMeters: 10_000, duration: .seconds(600))
        #expect(abs(progress(remaining: 5_000).remainingDuration(along: r).inSeconds - 300) < 0.5)
        #expect(abs(progress(remaining: 2_000).remainingDuration(along: r).inSeconds - 120) < 0.5)
    }

    @Test("is zero on arrival")
    func arrival() {
        let r = route()
        #expect(progress(remaining: 0, arrived: true).remainingDuration(along: r) == .zero)
    }

    @Test("clamps a remaining distance beyond the route length")
    func clampsOvershoot() {
        let r = route(distanceMeters: 10_000, duration: .seconds(600))
        #expect(abs(progress(remaining: 20_000).remainingDuration(along: r).inSeconds - 600) < 0.5)
    }

    @Test("is zero for a zero-length route")
    func zeroLengthRoute() {
        let r = route(distanceMeters: 0, duration: .seconds(600))
        #expect(progress(remaining: 100).remainingDuration(along: r) == .zero)
    }
}

// MARK: - RouteInfo builders

@Suite("RouteInfo")
struct RouteInfoTests {

    private let now = instant(hour: 15, minute: 45, timeZone: newYork)

    @Test("preview reports whole-route figures and ETA = now + duration")
    func preview() {
        let info = RouteInfo.preview(
            route: route(distanceMeters: 12_000, duration: .seconds(1_080)),
            now: now, locale: usEnglish, timeZone: newYork
        )
        #expect(info.kind == .preview)
        #expect(info.distanceText == "12 km")
        #expect(info.durationText == "18 min")
        #expect(info.etaDate == now.addingTimeInterval(1_080))
        #expect(info.etaText == RouteFormat.time(info.etaDate, locale: usEnglish, timeZone: newYork))
        #expect(info.etaText.contains("4:03")) // 15:45 + 18 min
    }

    @Test("remaining reports live figures and ETA = now + remaining duration")
    func remaining() {
        let info = RouteInfo.remaining(
            route: route(distanceMeters: 10_000, duration: .seconds(600)),
            progress: progress(remaining: 4_000),
            now: now, locale: usEnglish, timeZone: newYork
        )
        #expect(info.kind == .remaining)
        #expect(info.distanceText == "4.0 km")
        #expect(info.durationText == "4 min") // 600s * 0.4
        #expect(info.etaDate == now.addingTimeInterval(240))
    }

    @Test("arrival: zero distance, zero time, ETA is now")
    func arrival() {
        let info = RouteInfo.remaining(
            route: route(),
            progress: progress(remaining: 0, arrived: true),
            now: now, locale: usEnglish, timeZone: newYork
        )
        #expect(info.distanceText == "0 m")
        #expect(info.durationText == "< 1 min")
        #expect(info.etaDate == now)
    }

    @Test("a very small remaining distance formats cleanly")
    func tinyRemaining() {
        let info = RouteInfo.remaining(
            route: route(distanceMeters: 10_000, duration: .seconds(600)),
            progress: progress(remaining: 3),
            now: now, locale: usEnglish, timeZone: newYork
        )
        #expect(info.distanceText == "0 m")
        #expect(info.durationText == "< 1 min")
        #expect(info.etaDate.timeIntervalSince(now) < 1)
    }

    @Test("preview and live panels use different labels")
    func distinctLabels() {
        let preview = RouteInfo.Kind.preview.labels
        let live = RouteInfo.Kind.remaining.labels
        #expect(preview.distance == "Distance")
        #expect(preview.duration == "Time")
        #expect(preview.eta == "Arrival")
        #expect(live.distance == "Remaining")
        #expect(live.duration == "Time left")
        #expect(live.eta == "ETA")
        #expect(preview.distance != live.distance)
        #expect(preview.eta != live.eta)
    }
}

// MARK: - NavigationViewModel wiring

@MainActor
@Suite("NavigationViewModel routeInfo")
struct NavigationRouteInfoTests {

    private func navRoute() -> Route {
        let a = MapCoordinate(latitude: 0, longitude: 0)
        let b = MapCoordinate(latitude: 0, longitude: 0.045)
        let c = MapCoordinate(latitude: 0, longitude: 0.09)
        return Route(
            polyline: [a, b, c],
            distanceMeters: 10_000,
            duration: .seconds(900),
            steps: [
                RouteStep(maneuver: .depart, instruction: "Head east", roadName: "First St",
                          maneuverPoint: a, polyline: [a, b], distanceMeters: 0),
                RouteStep(maneuver: .arrive, instruction: "Arrive", roadName: nil,
                          maneuverPoint: b, polyline: [b, c], distanceMeters: 0),
            ]
        )
    }

    @Test("no info while inactive")
    func inactive() {
        #expect(NavigationViewModel().routeInfo() == nil)
    }

    @Test("live remaining info once navigating")
    func navigating() {
        let vm = NavigationViewModel()
        let r = navRoute()
        vm.start(route: r, from: r.steps[0].maneuverPoint)

        let info = try! #require(vm.routeInfo(now: instant(hour: 9, minute: 0, timeZone: newYork)))
        #expect(info.kind == .remaining)
        #expect(info.distanceText.isEmpty == false)
        #expect(info.etaDate > instant(hour: 9, minute: 0, timeZone: newYork))
    }

    @Test("no info after arrival (the maneuver card covers it)")
    func arrived() {
        let vm = NavigationViewModel()
        let r = navRoute()
        vm.start(route: r, from: r.steps[0].maneuverPoint)
        for i in 0..<(r.polyline.count - 1) {
            for f in stride(from: 0.0, through: 1.0, by: 0.1) {
                let p = MapCoordinate(
                    latitude: r.polyline[i].latitude + (r.polyline[i + 1].latitude - r.polyline[i].latitude) * f,
                    longitude: r.polyline[i].longitude + (r.polyline[i + 1].longitude - r.polyline[i].longitude) * f
                )
                vm.update(with: p)
            }
        }
        #expect(vm.state == .arrived)
        #expect(vm.routeInfo() == nil)
    }
}
