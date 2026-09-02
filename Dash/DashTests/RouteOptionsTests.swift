//
//  RouteOptionsTests.swift
//  DashTests
//
//  M4.5 — the SDK-neutral `RouteOptions` value type: construction, selection,
//  alternatives, and the compact `summaries` (duration / distance / relative
//  label) the selector control renders. Pure — no SDK, no view logic.
//

import Foundation
import Testing
@testable import Dash
import DashShared

private func route(_ id: String, distanceMeters: Double = 10_000, minutes: Double) -> Route {
    Route(id: id, polyline: [MapCoordinate(latitude: 0, longitude: 0),
                             MapCoordinate(latitude: 0, longitude: 0.05)],
          distanceMeters: distanceMeters, duration: .seconds(minutes * 60))
}

@Suite("RouteOptions")
struct RouteOptionsTests {

    @Test("an empty route list yields nil")
    func emptyIsNil() {
        #expect(RouteOptions([]) == nil)
    }

    @Test("a single route: no alternatives, it is selected + recommended")
    func singleRoute() {
        let opts = RouteOptions([route("route-0", minutes: 18)])!
        #expect(opts.routes.count == 1)
        #expect(opts.hasAlternatives == false)
        #expect(opts.selected.id == "route-0")
        #expect(opts.recommended.id == "route-0")
        #expect(opts.alternatives.isEmpty)
    }

    @Test("multiple routes: [0] recommended + selected by default, the rest are alternatives")
    func multipleRoutes() {
        let opts = RouteOptions([
            route("route-0", minutes: 18),
            route("route-1", minutes: 16),
            route("route-2", minutes: 22),
        ])!
        #expect(opts.hasAlternatives)
        #expect(opts.selected.id == "route-0")
        #expect(opts.alternatives.map(\.id) == ["route-1", "route-2"])
    }

    @Test("an explicit selectedID is honoured; an unknown one falls back to [0]")
    func explicitSelection() {
        let routes = [route("route-0", minutes: 18), route("route-1", minutes: 16)]
        #expect(RouteOptions(routes, selectedID: "route-1")!.selected.id == "route-1")
        #expect(RouteOptions(routes, selectedID: "nope")!.selected.id == "route-0")
    }

    @Test("selecting changes the selected route; an unknown id is ignored")
    func selecting() {
        let opts = RouteOptions([route("route-0", minutes: 18), route("route-1", minutes: 16)])!
        #expect(opts.selecting("route-1").selected.id == "route-1")
        #expect(opts.selecting("route-1").alternatives.map(\.id) == ["route-0"])
        #expect(opts.selecting("ghost").selected.id == "route-0") // unchanged
    }

    @Test("summaries: one per route, formatted, with the selection flagged")
    func summaries() {
        let opts = RouteOptions([
            route("route-0", distanceMeters: 12_000, minutes: 18),
            route("route-1", distanceMeters: 14_000, minutes: 16),
            route("route-2", distanceMeters: 11_000, minutes: 22),
        ])!.selecting("route-1")

        let s = opts.summaries
        #expect(s.count == 3)
        #expect(s.map(\.id) == ["route-0", "route-1", "route-2"])
        #expect(s[1].isSelected)
        #expect(s[0].isSelected == false)
        #expect(s[0].isRecommended)
        #expect(s[0].durationText == "18 min")
        #expect(s[0].distanceText == "12 km")
    }

    @Test("relative labels compare against the recommended route")
    func relativeLabels() {
        let opts = RouteOptions([
            route("route-0", minutes: 20),   // recommended
            route("route-1", minutes: 17),   // 3 min faster
            route("route-2", minutes: 25),   // 5 min longer
            route("route-3", minutes: 20.3), // ~similar
        ])!
        let labels = opts.summaries.map(\.label)
        #expect(labels[0] == "Recommended")
        #expect(labels[1] == "3 min faster")
        #expect(labels[2] == "5 min longer")
        #expect(labels[3] == "Similar time")
    }
}
