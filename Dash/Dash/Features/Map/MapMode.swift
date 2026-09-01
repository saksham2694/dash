//
//  MapMode.swift
//  Dash
//
//  What the map is currently for. `MapViewModel` reads this to decide how to
//  derive the camera (and, later, which overlays to surface). Today only
//  `.cruising` has distinct behaviour; the other cases are modelled so the
//  transitions can be filled in when routing and navigation land, without
//  touching `MapProvider` or `DashMapView`.
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
