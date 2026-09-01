//
//  MapProvider.swift
//  Dash
//
//  The map-*rendering* abstraction boundary (spec §5). A `MapProvider` wraps one
//  map SDK and does exactly one job: render a `MapContent` as a SwiftUI view and
//  report interaction back as `MapEvent`. Concrete SDK types (GMSMapView,
//  MKMapView, …) never cross this protocol.
//
//  Deliberately narrow. This protocol is *not* where search, autocomplete, place
//  details, or route computation live — those are separate service abstractions
//  (a later milestone) so a MapKit provider is not forced to reimplement Google's
//  Places/Routes stack. Everything the provider needs travels in `MapContent`;
//  everything it emits travels in `MapEvent`. New features extend those value
//  types, not this protocol.
//
//  Swapping providers — e.g. from a Settings toggle — stays a single assignment
//  on `MapViewModel.provider`.
//

import SwiftUI

/// Identifies a concrete map backend — used for the Settings toggle and logging.
nonisolated enum MapProviderID: String, CaseIterable, Sendable {
    case googleMaps
    case appleMaps // not implemented yet
}

@MainActor
protocol MapProvider {

    /// Stable identity of this backend.
    var id: MapProviderID { get }

    /// A SwiftUI view that renders `content` and keeps up as it changes.
    /// `onEvent` is called (on the main actor) for every user interaction.
    /// Type-erased so providers can be held in `any MapProvider`.
    func makeMapView(
        content: MapContent,
        onEvent: @escaping (MapEvent) -> Void
    ) -> AnyView
}
