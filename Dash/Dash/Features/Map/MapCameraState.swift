//
//  MapCameraState.swift
//  Dash
//
//  What the map should be showing, expressed in SDK-neutral terms (plain numbers).
//  This is the only "input" type that crosses the map abstraction boundary — no
//  GoogleMaps or MapKit types appear here.
//

import DashShared
import Foundation

struct MapCameraState: Equatable {

    /// Centre latitude in degrees (WGS 84).
    var latitude: Double

    /// Centre longitude in degrees (WGS 84).
    var longitude: Double

    /// Course over ground in degrees, clockwise from true north. `nil` when the
    /// heading is unknown — providers render north-up in that case.
    var headingDegrees: Double?

    /// Zoom on Google's ~0–21 scale. A future MapKit provider maps this to an
    /// altitude / distance.
    var zoom: Double

    /// A sensible starting camera before any fix has arrived.
    static let `default` = MapCameraState(
        latitude: 0,
        longitude: 0,
        headingDegrees: nil,
        zoom: 16
    )

    /// A copy of this camera re-centred on `packet`, keeping the current zoom.
    /// A negative packet heading (invalid fix) becomes `nil`.
    func following(_ packet: LocationPacket) -> MapCameraState {
        MapCameraState(
            latitude: packet.latitude,
            longitude: packet.longitude,
            headingDegrees: packet.heading >= 0 ? packet.heading : nil,
            zoom: zoom
        )
    }
}
