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

    /// `.navigating` camera framing (M4.2). Not turn-by-turn — just the camera
    /// shape: a moderate tilt, and the vehicle pushed this fraction of the
    /// viewport below centre so more of the road ahead is visible.
    static let navigationPitchDegrees: Double = 55
    static let navigationFocusBelowCentre: Double = 0.28

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
        camera = camera.following(packet)
        content.vehicle = VehicleIndicator(packet)
        if followsVehicle, mode != .destinationPreview {
            content.camera = followCameraPlan()
        }
    }

    /// Switch what the map is for. Any deliberate mode change re-arms
    /// `followsVehicle` and re-derives the camera immediately.
    func setMode(_ newMode: MapMode) {
        guard newMode != mode else { return }
        mode = newMode
        followsVehicle = true
        content.camera = cameraPlan()
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

        // Any existing route belongs to the previous destination — drop it until
        // the routing layer computes a new one via `setRoute(_:)`.
        self.route = nil
        content.polylines = []

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
    /// Draws the route as a single `MapPolyline`, and — **only while previewing a
    /// destination** — re-frames the `.fit` camera so the vehicle, destination
    /// and whole route are visible. That is a one-shot re-frame on route
    /// load/clear: a later fix still does not move the camera (`update(with:)`),
    /// so this is not navigation camera behaviour.
    func setRoute(_ route: Route?) {
        self.route = route

        if let route {
            content.polylines = [
                MapPolyline(id: Self.routePolylineID, coordinates: route.polyline)
            ]
        } else {
            content.polylines = []
        }

        if mode == .destinationPreview {
            content.camera = cameraPlan()
        }
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
    private func followCameraPlan() -> MapCameraPlan {
        switch mode {
        case .navigating:
            return .navigation(
                camera,
                pitchDegrees: Self.navigationPitchDegrees,
                focusBelowCentre: Self.navigationFocusBelowCentre
            )
        case .cruising, .destinationPreview:
            return .follow(camera)
        }
    }
}
