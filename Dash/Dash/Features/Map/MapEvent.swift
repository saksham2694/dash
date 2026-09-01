//
//  MapEvent.swift
//  Dash
//
//  What the rendered map reports back to `MapViewModel`: user taps and camera
//  movement. SDK-neutral — the provider translates its own delegate callbacks
//  (GMSMapViewDelegate, MKMapViewDelegate, …) into these cases.
//
//  Consumers of these events — destination selection, a "recenter" affordance,
//  off-route detection — arrive in later milestones. The channel exists now so
//  the provider protocol never has to grow a callback per feature.
//

import Foundation

/// A point of interest the map itself knows about (a labelled POI on the base
/// map), surfaced when the user taps it. The `placeID` feeds a future place
/// lookup.
nonisolated struct MapPOI: Equatable, Sendable {
    var placeID: String
    var name: String
    var coordinate: MapCoordinate
}

/// Where the camera came to rest after a move.
nonisolated struct MapCameraPosition: Equatable, Sendable {
    var center: MapCoordinate
    var zoom: Double
    var headingDegrees: Double
}

nonisolated enum MapEvent: Equatable, Sendable {

    /// The user tapped an empty part of the map.
    case tappedMap(MapCoordinate)

    /// The user tapped a labelled POI on the base map.
    case tappedPOI(MapPOI)

    /// The user tapped one of our `MapMarker`s (by `id`).
    case tappedMarker(id: String)

    /// The camera stopped moving. `byUserGesture` distinguishes a pan/zoom the
    /// user drove from a programmatic move the app drove.
    case cameraIdle(MapCameraPosition, byUserGesture: Bool)
}
