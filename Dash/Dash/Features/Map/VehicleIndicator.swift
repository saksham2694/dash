//
//  VehicleIndicator.swift
//  Dash
//
//  The SDK-neutral "you are here / this is the car" indicator (M4.1). Exactly one
//  per render — it is an intrinsic part of every map, not one of `MapContent`'s
//  overlay lists, and it is deliberately kept apart from `MapMarker` (destination
//  pins) so a provider can style it navigation-style rather than as a pin.
//
//  No GoogleMaps / MapKit / CoreLocation types appear here — the provider decides
//  how to draw a heading-less indicator (a plain location dot) versus one with a
//  usable heading (a directional pointer rotated to `headingDegrees`).
//

import DashShared
import Foundation

nonisolated struct VehicleIndicator: Equatable, Sendable {

    /// Where the vehicle currently is (WGS 84).
    var coordinate: MapCoordinate

    /// Course over ground, degrees clockwise from true north. `nil` when the
    /// latest fix carries no usable heading — the provider then shows a plain
    /// location dot instead of a directional pointer.
    var headingDegrees: Double?

    init(coordinate: MapCoordinate, headingDegrees: Double? = nil) {
        self.coordinate = coordinate
        self.headingDegrees = headingDegrees
    }

    /// Build from a relayed fix. A negative course (invalid, matching
    /// `CLLocation.course` semantics — see `LocationPacket.heading`) drops to no
    /// heading, exactly as `MapCameraState.following(_:)` treats it. No
    /// smoothing — the raw latest value is used.
    init(_ packet: LocationPacket) {
        self.init(
            coordinate: MapCoordinate(latitude: packet.latitude, longitude: packet.longitude),
            headingDegrees: packet.heading >= 0 ? packet.heading : nil
        )
    }
}
