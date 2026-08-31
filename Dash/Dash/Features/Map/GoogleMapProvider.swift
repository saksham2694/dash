//
//  GoogleMapProvider.swift
//  Dash
//
//  The Google Maps SDK for iOS implementation of `MapProvider`.
//
//  This is the ONLY file in Dash that imports GoogleMaps. Every GMS type stays
//  private to this file; the rest of the app sees only `MapProvider` /
//  `MapCameraState` / `DashMapView`.
//

import CoreLocation
import GoogleMaps
import SwiftUI

struct GoogleMapProvider: MapProvider {

    let id: MapProviderID = .googleMaps

    func makeMapView(camera: MapCameraState) -> AnyView {
        AnyView(GoogleMapContainer(camera: camera))
    }
}

/// Bridges `GMSMapView` into SwiftUI. Private: no GMS type escapes this file.
private struct GoogleMapContainer: UIViewRepresentable {

    let camera: MapCameraState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GMSMapView {
        let mapView = GMSMapView()
        mapView.camera = Self.cameraPosition(camera)
        mapView.settings.compassButton = true
        mapView.settings.rotateGestures = true
        // The camera is driven from LocationStore's relayed GPS, not the iPad's
        // own CoreLocation (it has no GPS chip) — so no "my location" blue dot.
        mapView.isMyLocationEnabled = false

        let marker = GMSMarker()
        marker.position = Self.coordinate(camera)
        marker.title = "Vehicle"
        // Keep the marker upright while the map rotates under it.
        marker.rotation = 0
        marker.map = mapView
        context.coordinator.vehicleMarker = marker

        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        mapView.animate(to: Self.cameraPosition(camera))
        context.coordinator.vehicleMarker?.position = Self.coordinate(camera)
    }

    /// Holds the marker so it can be moved across updates instead of recreated.
    final class Coordinator {
        var vehicleMarker: GMSMarker?
    }

    private static func coordinate(_ camera: MapCameraState) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: camera.latitude, longitude: camera.longitude)
    }

    private static func cameraPosition(_ camera: MapCameraState) -> GMSCameraPosition {
        GMSCameraPosition(
            latitude: camera.latitude,
            longitude: camera.longitude,
            zoom: Float(camera.zoom),
            bearing: camera.headingDegrees ?? 0,
            viewingAngle: 0
        )
    }
}
