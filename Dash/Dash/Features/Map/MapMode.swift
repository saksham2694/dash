//
//  MapMode.swift
//  Dash
//
//  What the map is currently for. `MapViewModel` reads this to decide how to
//  derive the camera (and, later, which overlays to surface). `.cruising` and
//  `.destinationPreview` (M3) and `.navigating`'s camera framing (M4.2) are
//  realised; guidance overlays for `.navigating` land in a later task. Nothing
//  currently drives the app *into* `.navigating` — there is no "start
//  navigation" UI yet.
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
