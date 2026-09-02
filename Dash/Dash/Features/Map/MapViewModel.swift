//
//  MapViewModel.swift
//  Dash
//
//  Drives the active map provider (spec §4). It owns the SDK-neutral render state
//  (`MapContent`) and the current `MapMode`, transforms location fed in from
//  outside into a camera, and routes `MapEvent`s coming back from the map.
//
//  It does NOT own or duplicate `LocationStore`, `DestinationStore`, or the
//  routing layer — no GPS, no networking, no watchdog here, and it holds no SDK
//  types. Location arrives via `update(with:)`, the chosen destination via
//  `setDestination(_:)`, and the computed route geometry via `setRoute(_:)`.
//
//  M4.2 adds vehicle-follow state: in `.cruising` / `.navigating` the camera
//  tracks the vehicle while `followsVehicle` is on; any user pan/zoom (reported
//  via `MapEvent.cameraIdle`) turns it off, and `recenter()` turns it back on
//  and snaps to the vehicle. `.destinationPreview` is unchanged (M3) — a
//  one-shot fit, never re-framed by a later fix.
//
//  M4.3 adds the navigation session: `startNavigation()` moves from
//  `.destinationPreview` into `.navigating`, and `setNavigationProgress(_:)`
//  feeds the live maneuver progress in (computed elsewhere by
//  `NavigationViewModel`). The navigation camera then zooms in as the vehicle
//  nears a significant maneuver and eases back out afterwards. Camera framing
//  only — the maneuver card, the progress engine, and all guidance logic live
//  outside this type.
//
//  M4.4 polish: while `.navigating`, the drawn route line is shortened to just
//  the part still ahead of the vehicle (derived from `route.polyline` +
//  `RouteGeometry`; the `Route` itself is never mutated), and the navigation
//  camera anchors the vehicle a little below centre.
//

import Combine
import DashShared
import Foundation

@MainActor
final class MapViewModel: ObservableObject {

    /// Inset (points) around the vehicle + destination when previewing.
    static let previewPadding: Double = 72

    /// Diffing id for the single active route line (M3). Stable so the provider
    /// updates the polyline in place when the route is recomputed.
    static let routePolylineID = "route"

    /// `.navigating` camera framing: a moderate tilt, with the vehicle indicator
    /// anchored a little below the vertical centre (M4.4 — `0.5` is dead centre)
    /// so more of the road ahead shows while staying well clear of the bottom
    /// route-info panel.
    static let navigationPitchDegrees: Double = 55
    static let navigationVehicleAnchor: Double = 0.6

    /// Dynamic navigation zoom (M4.3). The camera sits at `navigationBaseZoom`
    /// while cruising between maneuvers and tightens toward
    /// `navigationBaseZoom + navigationApproachZoomBoost` as the vehicle comes
    /// within `navigationApproachMeters` of a significant maneuver, easing back
    /// out once past it.
    nonisolated static let navigationBaseZoom: Double = 16
    nonisolated static let navigationApproachZoomBoost: Double = 1.5
    nonisolated static let navigationApproachMeters: Double = 350
    /// Distance at which the zoom-in reaches full boost.
    nonisolated static let navigationApproachFloorMeters: Double = 40

    /// The active backend. Reassign to switch providers (e.g. from Settings);
    /// nothing else in the dashboard changes.
    @Published var provider: any MapProvider

    /// Everything the provider should render right now. Rebuilt from the retained
    /// camera + latest vehicle position + mode + destination.
    @Published private(set) var content: MapContent

    /// What the map is currently for. Drives camera derivation.
    @Published private(set) var mode: MapMode

    /// Whether the camera tracks the vehicle on GPS updates (M4.2). On by
    /// default; any user pan/zoom turns it off (`handle(_:)`), `recenter()`
    /// turns it back on, and any deliberate mode change re-arms it.
    /// Irrelevant in `.destinationPreview` (that camera is one-shot).
    @Published private(set) var followsVehicle = true

    /// The retained vehicle-follow camera. Kept across fixes so zoom / heading
    /// persist; in `.cruising` / `.navigating` this is what a follow render
    /// shows. Not view state — it is an input to `content`, which is what the
    /// view observes.
    private(set) var camera: MapCameraState

    /// The chosen destination, mirrored here for camera math. `DestinationStore`
    /// remains the source of truth; this is set only via `setDestination(_:)`.
    private(set) var destination: Destination?

    /// The active route, mirrored here so the `.destinationPreview` camera can be
    /// framed around the whole route. The routing layer remains the source of
    /// truth; this is set only via `setRoute(_:)`.
    private(set) var route: Route?

    /// Live turn-by-turn progress while `.navigating` (M4.3). Owned by
    /// `NavigationViewModel`; mirrored here only so the navigation camera can
    /// zoom toward an upcoming maneuver. `nil` outside a navigation session.
    private(set) var navigationProgress: NavigationProgress?

    /// Whether at least one real GPS fix has been received. Gates
    /// `canStartNavigation` — routing to a maneuver needs a starting point.
    private(set) var hasReceivedFix = false

    convenience init() {
        self.init(provider: GoogleMapProvider())
    }

    init(provider: any MapProvider) {
        self.provider = provider
        self.mode = .cruising
        self.camera = .default
        self.content = MapContent(
            camera: .follow(.default),
            vehicle: VehicleIndicator(coordinate: MapCameraState.default.center)
        )
    }

    /// Feed in the latest known location. The caller owns `LocationStore`; this
    /// always moves the vehicle indicator (position + heading). The rendered
    /// camera moves with it **only** in `.cruising` / `.navigating` while
    /// `followsVehicle` is on — otherwise the vehicle moves under a fixed
    /// camera. `.destinationPreview` never moves the camera on a fix (M3).
    /// `nil` (no fix yet) leaves everything as-is.
    func update(with packet: LocationPacket?) {
        guard let packet else { return }
        hasReceivedFix = true
        camera = camera.following(packet)
        content.vehicle = VehicleIndicator(packet)
        if followsVehicle, mode != .destinationPreview {
            content.camera = followCameraPlan()
        }
        if mode == .navigating {
            refreshRoutePolyline() // shorten the line to the road still ahead (M4.4)
        }
    }

    /// Switch what the map is for. Any deliberate mode change re-arms
    /// `followsVehicle` and re-derives the camera immediately.
    func setMode(_ newMode: MapMode) {
        guard newMode != mode else { return }
        mode = newMode
        followsVehicle = true
        if newMode != .navigating {
            navigationProgress = nil
        }
        content.camera = cameraPlan()
        refreshRoutePolyline() // full route in preview/cruising, remaining while navigating (M4.4)
    }

    /// Enter turn-by-turn navigation from the route preview (M4.3). Requires a
    /// loaded route and a known current location (`canStartNavigation`); a no-op
    /// otherwise. Keeps the existing route, resets to the navigation base zoom,
    /// and switches to the `.navigating` camera.
    func startNavigation() {
        guard canStartNavigation else { return }
        navigationProgress = nil
        camera.zoom = Self.navigationBaseZoom
        setMode(.navigating)
    }

    /// Whether `startNavigation()` will do anything: previewing a destination,
    /// with a route and a current location. Drives the Start action's presence.
    var canStartNavigation: Bool {
        mode == .destinationPreview && route != nil && hasReceivedFix
    }

    /// Feed in the latest turn-by-turn progress (M4.3). Only meaningful while
    /// `.navigating`; when following, it re-derives the camera so the zoom
    /// tracks the distance to the upcoming maneuver.
    func setNavigationProgress(_ progress: NavigationProgress?) {
        navigationProgress = progress
        guard mode == .navigating, followsVehicle else { return }
        content.camera = followCameraPlan()
    }

    /// Re-enable vehicle-follow and snap the camera back to the vehicle now,
    /// using the framing appropriate to the current mode. No-op while previewing.
    func recenter() {
        guard mode != .destinationPreview else { return }
        followsVehicle = true
        content.camera = followCameraPlan()
    }

    /// Whether the composing view should show a "recenter / resume follow"
    /// affordance — i.e. follow is off in a mode where it applies.
    var showsRecenterButton: Bool {
        !followsVehicle && mode != .destinationPreview
    }

    /// Show (or clear) the chosen destination. A destination drops a pin, frames
    /// the vehicle + destination, and enters `.destinationPreview`; `nil` removes
    /// the pin and returns to vehicle-following `.cruising`.
    func setDestination(_ destination: Destination?) {
        self.destination = destination
        followsVehicle = true // a deliberate transition re-arms follow (M4.2)
        navigationProgress = nil // any nav session belonged to the old destination (M4.3)

        // Any existing route belongs to the previous destination — drop it until
        // the routing layer computes a new one via `setRoute(_:)`.
        self.route = nil
        refreshRoutePolyline() // clears the line (route is now nil)

        if let destination {
            content.markers = [
                MapMarker(
                    id: destination.placeID,
                    coordinate: destination.coordinate,
                    title: destination.name.isEmpty ? nil : destination.name
                )
            ]
            mode = .destinationPreview
        } else {
            content.markers = []
            mode = .cruising
        }
        content.camera = cameraPlan()
    }

    /// Show (or clear) the computed route geometry (M3).
    ///
    /// Draws the route as a single `MapPolyline` — the whole route while
    /// previewing / cruising, only the part still ahead of the vehicle while
    /// `.navigating` (M4.4). While previewing a destination it also re-frames the
    /// `.fit` camera once so the vehicle, destination and whole route are
    /// visible (a later fix still does not move that camera).
    func setRoute(_ route: Route?) {
        self.route = route
        refreshRoutePolyline()

        if mode == .destinationPreview {
            content.camera = cameraPlan()
        }
    }

    /// Rebuild `content.polylines` from `route`. During `.navigating` the line is
    /// clipped to `RouteGeometry.remainingPolyline` (the road still ahead of the
    /// vehicle); otherwise it is the whole route. Derived only — `route` is never
    /// mutated, and an empty result (arrived / no route) leaves no stale line.
    private func refreshRoutePolyline() {
        guard let route, route.polyline.count >= 2 else {
            content.polylines = []
            return
        }
        let coordinates = mode == .navigating
            ? RouteGeometry.remainingPolyline(of: route.polyline, from: content.vehicle.coordinate)
            : route.polyline
        content.polylines = coordinates.count >= 2
            ? [MapPolyline(id: Self.routePolylineID, coordinates: coordinates)]
            : []
    }

    /// Interaction coming back from the rendered map. `tapped*` cases are still
    /// documented-intent no-ops (routing turns a tap into a destination in a
    /// later task). `cameraIdle` from **any user gesture** turns `followsVehicle`
    /// off so the vehicle moves under a fixed camera until `recenter()`.
    /// Programmatic camera moves report `byUserGesture: false` and are ignored —
    /// no feedback loop.
    func handle(_ event: MapEvent) {
        switch event {
        case .tappedMap, .tappedPOI, .tappedMarker:
            break
        case .cameraIdle(let position, let byUserGesture):
            guard byUserGesture, mode != .destinationPreview else { return }
            followsVehicle = false
            // Remember the zoom the user left it at, so a later recenter /
            // resumed follow uses their zoom rather than snapping back.
            camera.zoom = position.zoom
        }
    }

    /// Camera intent for the current mode. `.cruising` / `.navigating` delegate
    /// to `followCameraPlan()`; `.destinationPreview` frames the vehicle +
    /// destination + route once (`update(with:)` then leaves it alone).
    private func cameraPlan() -> MapCameraPlan {
        switch mode {
        case .cruising, .navigating:
            return followCameraPlan()
        case .destinationPreview:
            guard let destination else { return .follow(camera) }
            var points = [content.vehicle.coordinate, destination.coordinate]
            points.append(contentsOf: route?.polyline ?? [])
            guard let bounds = MapCoordinateBounds(points) else { return .follow(camera) }
            return .fit(bounds, padding: Self.previewPadding)
        }
    }

    /// The vehicle-follow camera for the current mode: a plain centred follow
    /// while cruising, a tilted below-centre navigation framing while navigating.
    /// While navigating with live progress, the zoom tracks the distance to the
    /// upcoming significant maneuver (M4.3).
    private func followCameraPlan() -> MapCameraPlan {
        switch mode {
        case .navigating:
            return .navigation(
                navigationCameraState(),
                pitchDegrees: Self.navigationPitchDegrees,
                vehicleVerticalAnchor: Self.navigationVehicleAnchor
            )
        case .cruising, .destinationPreview:
            return .follow(camera)
        }
    }

    /// The camera position for a `.navigating` follow render: the retained
    /// follow camera, but with the zoom overridden by the dynamic navigation
    /// zoom when there is live maneuver progress. With no progress yet it is the
    /// retained camera unchanged (matching M4.2).
    private func navigationCameraState() -> MapCameraState {
        guard let progress = navigationProgress else { return camera }

        var approachingSignificant = false
        if let steps = route?.steps, steps.indices.contains(progress.stepIndex) {
            approachingSignificant = steps[progress.stepIndex].maneuver.warrantsCloserView
        }

        var state = camera
        state.zoom = Self.navigationZoom(
            base: Self.navigationBaseZoom,
            distanceToManeuverMeters: progress.isArrived ? nil : progress.distanceToManeuverMeters,
            approachingSignificantManeuver: approachingSignificant
        )
        return state
    }

    /// Pure dynamic-zoom curve (M4.3). Sits at `base` until the vehicle is
    /// within `navigationApproachMeters` of a significant maneuver, then ramps
    /// linearly to `base + navigationApproachZoomBoost` at
    /// `navigationApproachFloorMeters`. Quantised to 0.5 steps so the rendered
    /// zoom changes in a few discrete moves rather than nudging every fix.
    nonisolated static func navigationZoom(
        base: Double,
        distanceToManeuverMeters: Double?,
        approachingSignificantManeuver: Bool
    ) -> Double {
        guard
            approachingSignificantManeuver,
            let distance = distanceToManeuverMeters,
            distance < navigationApproachMeters
        else { return base }

        let span = navigationApproachMeters - navigationApproachFloorMeters
        let t = max(0, min(1, (navigationApproachMeters - distance) / span))
        let raw = base + navigationApproachZoomBoost * t
        return (raw * 2).rounded() / 2
    }
}
