//
//  MapMode.swift
//  Dash
//
//  What the map is currently for. `MapViewModel` reads this to decide how to
//  derive the camera and which overlays to surface. `.cruising` /
//  `.destinationPreview` (M3), the `.navigating` camera framing (M4.2), and the
//  turn-by-turn maneuver card + dynamic navigation zoom (M4.3) are all realised.
//  `MapViewModel.startNavigation()` drives the app into `.navigating` from the
//  route preview. Rerouting / off-route detection / voice guidance are out of
//  scope for M4.3.
//

import Foundation

nonisolated enum MapMode: Equatable, Sendable {

    /// Free driving — the camera follows the vehicle. The default.
    case cruising

    /// A destination has been chosen; the map frames the proposed route.
    case destinationPreview

    /// Actively navigating — follow camera with guidance overlays.
    case navigating
}
