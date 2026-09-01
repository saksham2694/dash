//
//  MapContent.swift
//  Dash
//
//  The complete, SDK-neutral description of what the map should render right now:
//  where the camera sits, where the vehicle is, and any overlays. `MapViewModel`
//  produces it; a `MapProvider` consumes it and diffs successive values.
//
//  This is the single "state in" value across the map-rendering boundary. Events
//  coming back out are `MapEvent`.
//

import Foundation

nonisolated struct MapContent: Equatable, Sendable {

    /// Where to place the camera on the next render.
    var camera: MapCameraPlan

    /// Current vehicle position — where the vehicle marker is drawn. Independent
    /// of `camera` so navigation can offset the camera ahead of the vehicle.
    /// Starts at `MapCameraState.default.center` until the first fix arrives.
    var vehicle: MapCoordinate

    /// Route lines to draw. Empty today; populated once routing lands.
    var polylines: [MapPolyline]

    /// Destination / result pins to draw. Empty today; populated once search
    /// and routing land.
    var markers: [MapMarker]

    init(
        camera: MapCameraPlan,
        vehicle: MapCoordinate,
        polylines: [MapPolyline] = [],
        markers: [MapMarker] = []
    ) {
        self.camera = camera
        self.vehicle = vehicle
        self.polylines = polylines
        self.markers = markers
    }
}
