//
//  Route.swift
//  Dash
//
//  The SDK-neutral domain model for a computed driving route (M3). No GoogleMaps
//  / Routes-API types appear here — `GoogleRouteService` translates its own
//  response into this at the boundary, exactly as `Destination` sits in front of
//  the Places SDK and `MapContent` in front of the renderer.
//
//  M3 needed only geometry to draw the route. M4.3 adds `steps` — the ordered
//  maneuvers for turn-by-turn guidance — populated by the provider from the same
//  response. `steps` is empty for a route computed without step data (older
//  callers, canned test fixtures); the overview `polyline` is always present.
//  `distance` / `duration` fall straight out of the same response.
//

import Foundation

/// A single driving route from an origin to a destination.
nonisolated struct Route: Equatable, Sendable {

    /// The full path, decoded to plain WGS-84 coordinates in travel order.
    /// The map layer renders this as a `MapPolyline`.
    var polyline: [MapCoordinate]

    /// Total driving distance along `polyline`, in metres.
    var distanceMeters: Double

    /// Estimated driving time for the route. `.zero` when the provider omits it.
    var duration: Duration

    /// Ordered maneuvers from origin to destination (M4.3). Empty when the route
    /// was computed without step data. The guidance engine and maneuver card
    /// read this; the drawn polyline stays `polyline`.
    var steps: [RouteStep]

    init(
        polyline: [MapCoordinate],
        distanceMeters: Double,
        duration: Duration,
        steps: [RouteStep] = []
    ) {
        self.polyline = polyline
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.steps = steps
    }
}
