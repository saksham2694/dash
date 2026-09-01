//
//  PlaceSearchService.swift
//  Dash
//
//  The provider-neutral place-search abstraction. Deliberately a *separate*
//  protocol from `MapProvider` — search / autocomplete / place details are not a
//  rendering concern, and a future MapKit path uses `MKLocalSearchCompleter` /
//  `MKLocalSearch`, not Google's stack. `MapProvider` never grows these methods.
//
//  Implementations: `GooglePlaceSearchService` (Places SDK) today; an Apple one
//  later. Callers depend only on this protocol.
//

import Foundation

@MainActor
protocol PlaceSearchService {

    /// Autocomplete suggestions for a partial `query`, biased towards `origin`
    /// (the vehicle position) when known. Returns `[]` for a query too short to
    /// be worth a lookup — callers should still guard, but this must not throw
    /// for that case.
    func suggestions(matching query: String, near origin: MapCoordinate?) async throws -> [PlaceSuggestion]

    /// Resolve a suggestion's `placeID` into a full `Destination` (name,
    /// address, coordinate).
    func details(for placeID: String) async throws -> Destination
}

/// Failure surfaced to the search UI. Kept coarse on purpose — the UI only shows
/// a single "couldn't search" affordance.
enum PlaceSearchError: Error, Equatable {

    /// The place lookup returned no usable result.
    case placeNotFound

    /// The provider isn't configured / reachable (e.g. no API key, offline).
    case unavailable
}
