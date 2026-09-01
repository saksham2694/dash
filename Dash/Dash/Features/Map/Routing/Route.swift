//
//  Route.swift
//  Dash
//
//  The SDK-neutral domain model for a computed driving route (M3). No GoogleMaps
//  / Routes-API types appear here — `GoogleRouteService` translates its own
//  response into this at the boundary, exactly as `Destination` sits in front of
//  the Places SDK and `MapContent` in front of the renderer.
//
//  Deliberately minimal: geometry is all M3 needs to draw the route. `distance`
//  and `duration` are kept because they fall straight out of the same response
//  and the guidance / trip layers (M4+) will want them — they are NOT a visible
//  navigation UI feature in M3.
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

    init(polyline: [MapCoordinate], distanceMeters: Double, duration: Duration) {
        self.polyline = polyline
        self.distanceMeters = distanceMeters
        self.duration = duration
    }
}
