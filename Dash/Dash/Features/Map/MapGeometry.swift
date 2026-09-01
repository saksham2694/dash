//
//  MapGeometry.swift
//  Dash
//
//  SDK-neutral geometry primitives for the map abstraction. No GoogleMaps,
//  MapKit, or CoreLocation types appear here — providers translate to and from
//  their own coordinate types at the boundary.
//

import Foundation

/// A geographic point (WGS 84), in degrees.
nonisolated struct MapCoordinate: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

/// An axis-aligned lat/long box — the region a route (or any coordinate set)
/// occupies. Used to ask a provider to frame that region ("route preview").
nonisolated struct MapCoordinateBounds: Equatable, Sendable {

    /// Minimum latitude / minimum longitude corner.
    var southWest: MapCoordinate

    /// Maximum latitude / maximum longitude corner.
    var northEast: MapCoordinate

    init(southWest: MapCoordinate, northEast: MapCoordinate) {
        self.southWest = southWest
        self.northEast = northEast
    }

    /// The tightest box containing every coordinate. `nil` if the set is empty.
    /// A single coordinate yields a degenerate (zero-area) box.
    init?(_ coordinates: [MapCoordinate]) {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        self.southWest = MapCoordinate(latitude: minLat, longitude: minLon)
        self.northEast = MapCoordinate(latitude: maxLat, longitude: maxLon)
    }

    /// Geometric centre of the box.
    var center: MapCoordinate {
        MapCoordinate(
            latitude: (southWest.latitude + northEast.latitude) / 2,
            longitude: (southWest.longitude + northEast.longitude) / 2
        )
    }
}
