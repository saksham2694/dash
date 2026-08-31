//
//  MapProvider.swift
//  Dash
//
//  The map abstraction boundary (spec §5). A `MapProvider` wraps one map SDK and
//  exposes *only* a SwiftUI view driven by neutral `MapCameraState`. Concrete SDK
//  types (GMSMapView, MKMapView, …) never cross this protocol.
//
//  Swapping providers — e.g. from a Settings toggle — is a single assignment on
//  `MapViewModel.provider`; `LocationStore`, `DashMapView`, and the rest of the
//  dashboard are untouched.
//
//  Display only for now. Search and routing will extend this protocol in later
//  tasks; they are deliberately absent here.
//

import SwiftUI

/// Identifies a concrete map backend — used for the Settings toggle and logging.
enum MapProviderID: String, CaseIterable, Sendable {
    case googleMaps
    case appleMaps // not implemented yet
}

@MainActor
protocol MapProvider {

    /// Stable identity of this backend.
    var id: MapProviderID { get }

    /// A SwiftUI view that renders `camera` and keeps up as `camera` changes.
    /// Type-erased so providers can be held in `any MapProvider` and swapped at runtime.
    func makeMapView(camera: MapCameraState) -> AnyView
}
