//
//  MapOverlay.swift
//  Dash
//
//  SDK-neutral descriptions of things drawn on top of the base map: routes,
//  destination pins, and (later) other overlays. Each is an identified value so
//  the provider can diff successive renders and move / reuse its own objects
//  rather than tear them down and rebuild.
//
//  The current-location / vehicle indicator is deliberately NOT modelled here —
//  it is an intrinsic part of every map render, there is exactly one, and it has
//  its own navigation-style presentation. It lives in `MapContent.vehicle` as a
//  `VehicleIndicator`, driven straight from the location pipeline.
//

import Foundation

/// A connected line drawn on the map, e.g. a computed route.
nonisolated struct MapPolyline: Equatable, Identifiable, Sendable {

    /// Stable identity across renders (e.g. the route id). Diffing key.
    let id: String

    /// Ordered points, in draw order.
    var coordinates: [MapCoordinate]
}

/// A pin dropped on the map, e.g. the chosen destination or a search result.
nonisolated struct MapMarker: Equatable, Identifiable, Sendable {

    /// Stable identity across renders. Diffing key, and echoed back in
    /// `MapEvent.tappedMarker`.
    let id: String

    /// Where the pin sits.
    var coordinate: MapCoordinate

    /// Optional label shown by the provider (info window / callout).
    var title: String?
}
