//
//  MapDashboardCamera.swift
//  Dash
//
//  The camera a Map *dashboard widget* frames itself with (M5.2.1). Deliberately
//  simpler than the full-screen camera (`MapViewModel.cameraPlan()`): a widget is
//  a glanceable tile, so it just auto-centres on the vehicle — no pitch, no
//  user pan/zoom, no route-preview fit, no manual-follow toggle.
//
//  Pure and SDK-neutral so it is trivially unit-testable. The full-screen
//  camera-follow behaviour is untouched — widgets never call into it.
//

import Foundation

nonisolated enum MapDashboardCamera {

    /// What the widget map is currently for.
    enum Style: Equatable, Sendable {
        /// Free driving — north-up, a calmer wide zoom.
        case cruising
        /// A navigation session is active — heading-up, tighter road-level zoom.
        case navigating
    }

    /// Google's ~0–21 zoom scale.
    static let cruisingZoom = 14.5
    static let navigatingZoom = 16.0

    /// The camera plan for a widget map centred on `vehicle`.
    ///
    /// - `heading` is only applied (heading-up) while `.navigating`; `.cruising`
    ///   stays north-up so a parked / slow glance isn't spun around by GPS
    ///   course jitter. A negative / non-finite heading is treated as unknown.
    static func plan(style: Style, vehicle: MapCoordinate, heading: Double?) -> MapCameraPlan {
        let bearing: Double? = {
            guard style == .navigating, let heading, heading >= 0, heading.isFinite else { return nil }
            return heading
        }()
        return .follow(
            MapCameraState(
                latitude: vehicle.latitude,
                longitude: vehicle.longitude,
                headingDegrees: bearing,
                zoom: style == .navigating ? navigatingZoom : cruisingZoom
            )
        )
    }
}
