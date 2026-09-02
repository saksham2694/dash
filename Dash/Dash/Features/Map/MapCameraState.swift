//
//  MapCameraState.swift
//  Dash
//
//  What the map camera should be showing, expressed in SDK-neutral terms (plain
//  numbers). No GoogleMaps or MapKit types appear here.
//
//  Shapes of camera intent modelled:
//    - `MapCameraPlan.follow` — centre on a concrete `MapCameraState`
//      (centre / heading / zoom); the cruising vehicle-follow case.
//    - `MapCameraPlan.fit` — "frame this region", resolved by the provider
//      against its own viewport size; the route-preview case (M3).
//    - `MapCameraPlan.navigation` — like `follow` but tilted and with the focal
//      point pushed down so the vehicle sits below centre and more map is
//      visible ahead; the `.navigating` case (M4.2). Still SDK-neutral — the
//      provider turns the pitch / below-centre fraction into its own camera.
//

import DashShared
import Foundation

nonisolated struct MapCameraState: Equatable, Sendable {

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

    /// The centre point as a coordinate.
    var center: MapCoordinate {
        MapCoordinate(latitude: latitude, longitude: longitude)
    }

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

/// How the provider should place its camera on the next render.
nonisolated enum MapCameraPlan: Equatable, Sendable {

    /// Centre on a concrete position — the cruising vehicle-follow case.
    case follow(MapCameraState)

    /// Frame a region with `padding` points of inset on every edge. The provider
    /// computes the centre and zoom from its own viewport. Used for route preview.
    case fit(MapCoordinateBounds, padding: Double)

    /// Navigation framing (M4.2): centre on `state`, tilt the camera by
    /// `pitchDegrees`, and shift the focal point down by `focusBelowCentre` of
    /// the viewport height so the vehicle sits below centre with more map ahead.
    /// The provider renders `state.headingDegrees` as the camera bearing.
    case navigation(MapCameraState, pitchDegrees: Double, focusBelowCentre: Double)
}
