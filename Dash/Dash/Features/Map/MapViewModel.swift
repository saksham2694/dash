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

    /// The active backend. Reassign to switch providers (e.g. from Settings);
    /// nothing else in the dashboard changes.
    @Published var provider: any MapProvider

    /// Everything the provider should render right now. Rebuilt from the retained
    /// camera + latest vehicle position + mode + destination.
    @Published private(set) var content: MapContent

    /// What the map is currently for. Drives camera derivation.
    @Published private(set) var mode: MapMode

    /// The retained vehicle-follow camera. Kept across fixes so zoom / heading
    /// persist; in `.cruising` this is what the map shows. Not view state — it is
    /// an input to `content`, which is what the view observes.
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
            vehicle: MapCameraState.default.center
        )
    }

    /// Feed in the latest known location. The caller owns `LocationStore`; this
    /// re-centres the follow camera and moves the vehicle. `nil` (no fix yet)
    /// leaves everything as-is. While previewing a destination the camera is left
    /// framed on the preview — only the vehicle marker moves.
    func update(with packet: LocationPacket?) {
        guard let packet else { return }
        camera = camera.following(packet)
        content.vehicle = MapCoordinate(latitude: packet.latitude, longitude: packet.longitude)
        if mode != .destinationPreview {
            content.camera = .follow(camera)
        }
    }

    /// Switch what the map is for. Camera is re-derived immediately.
    func setMode(_ newMode: MapMode) {
        guard newMode != mode else { return }
        mode = newMode
        content.camera = cameraPlan()
    }

    /// Show (or clear) the chosen destination. A destination drops a pin, frames
    /// the vehicle + destination, and enters `.destinationPreview`; `nil` removes
    /// the pin and returns to vehicle-following `.cruising`.
    func setDestination(_ destination: Destination?) {
        self.destination = destination

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

    /// Interaction coming back from the rendered map. The channel is SDK-neutral;
    /// consumers (routing, "recenter", off-route detection) are wired in later
    /// milestones, so today these cases only document intent.
    func handle(_ event: MapEvent) {
        switch event {
        case .tappedMap, .tappedPOI, .tappedMarker:
            break // routing milestone: turn a tap into a destination
        case .cameraIdle:
            break // navigation milestone: drop out of follow when the user pans
        }
    }

    /// Camera intent for the current mode. `.destinationPreview` frames the
    /// vehicle + destination + route (when a route has loaded) once;
    /// `update(with:)` then leaves it alone so the view doesn't jump on every fix.
    private func cameraPlan() -> MapCameraPlan {
        switch mode {
        case .cruising, .navigating:
            return .follow(camera)
        case .destinationPreview:
            guard let destination else { return .follow(camera) }
            var points = [content.vehicle, destination.coordinate]
            points.append(contentsOf: route?.polyline ?? [])
            guard let bounds = MapCoordinateBounds(points) else { return .follow(camera) }
            return .fit(bounds, padding: Self.previewPadding)
        }
    }
}
