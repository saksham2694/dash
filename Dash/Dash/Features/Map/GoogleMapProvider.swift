//
//  GoogleMapProvider.swift
//  Dash
//
//  The Google Maps SDK for iOS implementation of `MapProvider`.
//
//  This is the ONLY file in Dash that imports GoogleMaps. Every GMS type stays
//  private to this file; the rest of the app sees only the SDK-neutral map types
//  (`MapContent`, `MapCameraPlan`, `MapPolyline`, `MapMarker`, `VehicleIndicator`,
//  `MapEvent`, …).
//

import CoreLocation
import GoogleMaps
import SwiftUI
import UIKit

struct GoogleMapProvider: MapProvider {

    let id: MapProviderID = .googleMaps

    func makeMapView(
        content: MapContent,
        onEvent: @escaping (MapEvent) -> Void
    ) -> AnyView {
        AnyView(GoogleMapContainer(content: content, onEvent: onEvent))
    }

    /// How to draw the current-location indicator (M4.1). Pure and SDK-free so it
    /// can be unit-tested without a `GMSMapView`: a plain location dot when the
    /// fix carries no usable heading, or a pointer rotated to the bearing when it
    /// does. Never styled like a destination `MapMarker`.
    nonisolated enum VehicleStyle: Equatable {
        case locationDot
        case directionalPointer(rotationDegrees: Double)
    }

    nonisolated static func vehicleStyle(for vehicle: VehicleIndicator) -> VehicleStyle {
        if let heading = vehicle.headingDegrees {
            return .directionalPointer(rotationDegrees: heading)
        }
        return .locationDot
    }

    /// Tracks whether the camera movement settling right now was driven by the
    /// user (M4.2). GMS reports `willMove(byGesture:)` before every camera
    /// change; a user pan/zoom/rotate latches this on and `idleAt` consumes it.
    /// The latch is deliberate: a programmatic follow animation can fire
    /// *between* a gesture starting and the camera going idle, reporting
    /// `byGesture: false` — that must not erase the fact that the user is
    /// interacting. There is no distance or zoom threshold: any real gesture,
    /// however small, ends up reported as user-driven. Pure and SDK-free.
    nonisolated struct UserGestureLatch: Equatable {
        private(set) var isUserDriven = false

        mutating func willMove(byGesture: Bool) {
            if byGesture { isUserDriven = true }
        }

        /// Read the latch and clear it — call once per `idleAt`.
        mutating func consumeOnIdle() -> Bool {
            defer { isUserDriven = false }
            return isUserDriven
        }
    }
}

/// Bridges `GMSMapView` into SwiftUI. Private: no GMS type escapes this file.
private struct GoogleMapContainer: UIViewRepresentable {

    let content: MapContent
    let onEvent: (MapEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> GMSMapView {
        let mapView = GMSMapView()
        mapView.settings.compassButton = true
        mapView.settings.rotateGestures = true
        // The camera is driven from LocationStore's relayed GPS, not the iPad's
        // own CoreLocation (it has no GPS chip) — so no "my location" blue dot.
        mapView.isMyLocationEnabled = false
        mapView.delegate = context.coordinator

        // The current-location / vehicle indicator (M4.1). Flat so its rotation
        // tracks the true bearing as the map rotates under it; not tappable; no
        // callout. Its icon + rotation are set by `syncVehicle(_:on:)`.
        let marker = GMSMarker()
        marker.isFlat = true
        marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
        marker.isTappable = false
        marker.zIndex = 1 // sit on top of the route polyline
        marker.map = mapView
        context.coordinator.vehicleMarker = marker

        context.coordinator.apply(content, to: mapView, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.apply(content, to: mapView, animated: true)
    }

    /// Owns the mutable GMS objects so they are moved / reused across renders
    /// instead of recreated, and translates `GMSMapViewDelegate` callbacks into
    /// `MapEvent`s.
    final class Coordinator: NSObject, GMSMapViewDelegate {

        var onEvent: (MapEvent) -> Void
        var vehicleMarker: GMSMarker?

        private var routeLines: [String: GMSPolyline] = [:]
        private var pins: [String: GMSMarker] = [:]
        private var applied: MapContent?
        /// Whether the camera settling now was driven by the user (M4.2).
        private var gestureLatch = GoogleMapProvider.UserGestureLatch()

        init(onEvent: @escaping (MapEvent) -> Void) {
            self.onEvent = onEvent
        }

        /// Diff `content` against the last render and apply only what changed.
        func apply(_ content: MapContent, to mapView: GMSMapView, animated: Bool) {
            guard content != applied else { return }
            let previous = applied
            applied = content

            if previous?.camera != content.camera {
                applyCamera(content.camera, to: mapView, animated: animated)
            }
            if previous?.vehicle != content.vehicle {
                syncVehicle(content.vehicle, on: mapView)
            }
            if previous?.polylines != content.polylines {
                syncPolylines(content.polylines, on: mapView)
            }
            if previous?.markers != content.markers {
                syncMarkers(content.markers, on: mapView)
            }
        }

        // MARK: - Rendering

        private func applyCamera(_ plan: MapCameraPlan, to mapView: GMSMapView, animated: Bool) {
            switch plan {
            case .follow(let state):
                mapView.padding = .zero
                move(mapView, to: state, pitch: 0, animated: animated)

            case .navigation(let state, let pitch, let belowCentre):
                // Push the visual centre down so the vehicle sits below it and
                // more road ahead is on screen.
                let inset = max(0, mapView.bounds.height * CGFloat(belowCentre))
                mapView.padding = UIEdgeInsets(top: 0, left: 0, bottom: inset, right: 0)
                move(mapView, to: state, pitch: pitch, animated: animated)

            case .fit(let bounds, let padding):
                mapView.padding = .zero
                let gmsBounds = GMSCoordinateBounds(
                    coordinate: Self.coordinate(bounds.southWest),
                    coordinate: Self.coordinate(bounds.northEast)
                )
                let update = GMSCameraUpdate.fit(gmsBounds, withPadding: padding)
                if animated {
                    mapView.animate(with: update)
                } else {
                    mapView.moveCamera(update)
                }
            }
        }

        private func move(_ mapView: GMSMapView, to state: MapCameraState, pitch: Double, animated: Bool) {
            let position = GMSCameraPosition(
                latitude: state.latitude,
                longitude: state.longitude,
                zoom: Float(state.zoom),
                bearing: state.headingDegrees ?? 0,
                viewingAngle: pitch
            )
            if animated {
                mapView.animate(to: position)
            } else {
                mapView.camera = position
            }
        }

        private func syncPolylines(_ lines: [MapPolyline], on mapView: GMSMapView) {
            var stale = Set(routeLines.keys)
            for line in lines {
                stale.remove(line.id)
                let path = GMSMutablePath()
                for coordinate in line.coordinates {
                    path.add(Self.coordinate(coordinate))
                }
                if let existing = routeLines[line.id] {
                    existing.path = path
                } else {
                    let polyline = GMSPolyline(path: path)
                    polyline.strokeWidth = 6
                    polyline.strokeColor = .systemBlue
                    polyline.map = mapView
                    routeLines[line.id] = polyline
                }
            }
            for id in stale {
                routeLines[id]?.map = nil
                routeLines[id] = nil
            }
        }

        private func syncMarkers(_ markers: [MapMarker], on mapView: GMSMapView) {
            var stale = Set(pins.keys)
            for marker in markers {
                stale.remove(marker.id)
                if let existing = pins[marker.id] {
                    existing.position = Self.coordinate(marker.coordinate)
                    existing.title = marker.title
                } else {
                    let pin = GMSMarker()
                    pin.position = Self.coordinate(marker.coordinate)
                    pin.title = marker.title
                    pin.userData = marker.id
                    pin.map = mapView
                    pins[marker.id] = pin
                }
            }
            for id in stale {
                pins[id]?.map = nil
                pins[id] = nil
            }
        }

        /// Move + restyle the single current-location indicator (M4.1). Reuses
        /// the one marker created in `makeUIView` — never recreated.
        private func syncVehicle(_ vehicle: VehicleIndicator, on mapView: GMSMapView) {
            guard let marker = vehicleMarker else { return }
            marker.position = Self.coordinate(vehicle.coordinate)
            switch GoogleMapProvider.vehicleStyle(for: vehicle) {
            case .locationDot:
                marker.icon = Self.locationDotImage
                marker.rotation = 0
            case .directionalPointer(let rotationDegrees):
                marker.icon = Self.directionalPointerImage
                marker.rotation = rotationDegrees
            }
        }

        // MARK: - Vehicle-indicator icons (drawn once, then cached)

        /// A blue "you are here" dot with a white ring — shown when no usable
        /// heading is available. Distinct from the red destination pin.
        private static let locationDotImage: UIImage = {
            let side: CGFloat = 24
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            return renderer.image { context in
                let cg = context.cgContext
                let ring = CGRect(x: 1, y: 1, width: side - 2, height: side - 2)
                cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.3).cgColor)
                UIColor.white.setFill()
                cg.fillEllipse(in: ring)
                UIColor.systemBlue.setFill()
                cg.fillEllipse(in: ring.insetBy(dx: 3, dy: 3))
            }
        }()

        /// A blue arrowhead pointing "up" at rotation 0 (i.e. toward heading 0 /
        /// true north). `syncVehicle` sets `marker.rotation` to the bearing.
        private static let directionalPointerImage: UIImage = {
            let side: CGFloat = 32
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            return renderer.image { context in
                let path = UIBezierPath()
                path.move(to: CGPoint(x: side / 2, y: 3))               // tip
                path.addLine(to: CGPoint(x: side - 5, y: side - 4))     // bottom-right
                path.addLine(to: CGPoint(x: side / 2, y: side - 10))    // tail notch
                path.addLine(to: CGPoint(x: 5, y: side - 4))            // bottom-left
                path.close()
                path.lineJoinStyle = .round
                path.lineWidth = 3
                UIColor.systemBlue.setFill()
                path.fill()
                UIColor.white.setStroke()
                path.stroke()
            }
        }()

        // MARK: - GMSMapViewDelegate

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            gestureLatch.willMove(byGesture: gesture)
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            let settled = MapCameraPosition(
                center: MapCoordinate(
                    latitude: position.target.latitude,
                    longitude: position.target.longitude
                ),
                zoom: Double(position.zoom),
                headingDegrees: position.bearing
            )
            onEvent(.cameraIdle(settled, byUserGesture: gestureLatch.consumeOnIdle()))
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            onEvent(.tappedMap(MapCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )))
        }

        func mapView(
            _ mapView: GMSMapView,
            didTapPOIWithPlaceID placeID: String,
            name: String,
            location: CLLocationCoordinate2D
        ) {
            onEvent(.tappedPOI(MapPOI(
                placeID: placeID,
                name: name,
                coordinate: MapCoordinate(
                    latitude: location.latitude,
                    longitude: location.longitude
                )
            )))
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let id = marker.userData as? String else { return false }
            onEvent(.tappedMarker(id: id))
            return false // keep default behaviour (centre + info window)
        }

        private static func coordinate(_ c: MapCoordinate) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
        }
    }
}
