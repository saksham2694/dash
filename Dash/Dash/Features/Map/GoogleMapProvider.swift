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

    func makeUIView(context: Context) -> GMSMapView {
        let mapView = GMSMapView()
        mapView.camera = Self.cameraPosition(camera)
        mapView.settings.compassButton = true
        mapView.settings.rotateGestures = true
        // The camera is driven from LocationStore, not the device's own GPS.
        mapView.isMyLocationEnabled = false
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        mapView.animate(to: Self.cameraPosition(camera))
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
