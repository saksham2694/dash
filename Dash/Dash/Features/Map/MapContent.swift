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

    /// The current-location / vehicle indicator — position plus heading (M4.1).
    /// Independent of `camera` so navigation can later offset the camera ahead of
    /// the vehicle. Starts at `MapCameraState.default.center` with no heading
    /// until the first fix arrives. Distinct from `markers` (destination pins).
    var vehicle: VehicleIndicator

    /// Route lines to draw. Empty today; populated once routing lands.
    var polylines: [MapPolyline]

    /// Destination / result pins to draw. Empty today; populated once search
    /// and routing land.
    var markers: [MapMarker]

    init(
        camera: MapCameraPlan,
        vehicle: VehicleIndicator,
        polylines: [MapPolyline] = [],
        markers: [MapMarker] = []
    ) {
        self.camera = camera
        self.vehicle = vehicle
        self.polylines = polylines
        self.markers = markers
    }
}
