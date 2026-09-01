//
//  GoogleMapProvider.swift
//  Dash
//
//  The Google Maps SDK for iOS implementation of `MapProvider`.
//
//  This is the ONLY file in Dash that imports GoogleMaps. Every GMS type stays
//  private to this file; the rest of the app sees only the SDK-neutral map types
//  (`MapContent`, `MapCameraPlan`, `MapPolyline`, `MapMarker`, `MapEvent`, …).
//

import CoreLocation
import GoogleMaps
import SwiftUI

struct GoogleMapProvider: MapProvider {

    let id: MapProviderID = .googleMaps

    func makeMapView(
        content: MapContent,
        onEvent: @escaping (MapEvent) -> Void
    ) -> AnyView {
        AnyView(GoogleMapContainer(content: content, onEvent: onEvent))
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

        let marker = GMSMarker()
        marker.title = "Vehicle"
        // Keep the marker upright while the map rotates under it.
        marker.rotation = 0
        marker.isTappable = false
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
        private var gestureInProgress = false

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
                vehicleMarker?.position = Self.coordinate(content.vehicle)
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
                let position = GMSCameraPosition(
                    latitude: state.latitude,
                    longitude: state.longitude,
                    zoom: Float(state.zoom),
                    bearing: state.headingDegrees ?? 0,
                    viewingAngle: 0
                )
                if animated {
                    mapView.animate(to: position)
                } else {
                    mapView.camera = position
                }

            case .fit(let bounds, let padding):
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

        // MARK: - GMSMapViewDelegate

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            gestureInProgress = gesture
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            let byUser = gestureInProgress
            gestureInProgress = false
            onEvent(.cameraIdle(
                MapCameraPosition(
                    center: MapCoordinate(
                        latitude: position.target.latitude,
                        longitude: position.target.longitude
                    ),
                    zoom: Double(position.zoom),
                    headingDegrees: position.bearing
                ),
                byUserGesture: byUser
            ))
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
