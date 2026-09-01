//
//  Destination.swift
//  Dash
//
//  SDK-neutral value types for place search and the chosen destination. No
//  GooglePlaces / GoogleMaps / MapKit types appear here — the search service
//  translates its own results into these at the boundary (mirrors how
//  `MapCoordinate` / `MapContent` sit in front of the map renderer).
//

import Foundation

/// One row of an autocomplete result list. `placeID` is an opaque, stable
/// identifier for the place (Google Place ID today; Apple exposes an equivalent).
/// It is the handle used to fetch full details.
nonisolated struct PlaceSuggestion: Equatable, Sendable, Identifiable {

    var placeID: String

    /// The prominent line — the business or place name, e.g. "Starbucks".
    var primaryText: String

    /// Supporting context that tells otherwise-identical results apart —
    /// locality / area / street, e.g. "MG Road, Bengaluru". `nil` when the
    /// provider gives nothing beyond the name.
    var secondaryText: String?

    /// Straight-line distance from the vehicle in metres, when a position is
    /// known. Drives the trailing "1.2 km" label (à la Apple Maps).
    var distanceMeters: Double?

    /// Coarse kind of place — used *only* to pick the leading result-row glyph.
    var category: PlaceCategory

    var id: String { placeID }

    init(
        placeID: String,
        primaryText: String,
        secondaryText: String? = nil,
        distanceMeters: Double? = nil,
        category: PlaceCategory = .place
    ) {
        self.placeID = placeID
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.distanceMeters = distanceMeters
        self.category = category
    }
}

/// Deliberately coarse, SDK-neutral place category. Exists only so the search
/// list can show a recognisable leading glyph; never used for routing or logic.
nonisolated enum PlaceCategory: Equatable, Sendable {
    case food
    case cafe
    case shopping
    case fuel
    case lodging
    case transit
    case landmark
    /// A locality / area / street rather than a specific venue.
    case geographic
    /// Unknown / generic.
    case place
}

/// A resolved place the driver has chosen to head to. This is what the rest of
/// the app (map pin now; routing later) works with.
nonisolated struct Destination: Equatable, Sendable, Identifiable {

    /// Opaque stable place identifier (see `PlaceSuggestion.placeID`).
    var placeID: String

    /// Display name, e.g. "Kempegowda International Airport".
    var name: String

    /// Formatted address, when the provider returned one.
    var address: String?

    /// Where the pin goes / where routing will target.
    var coordinate: MapCoordinate

    var id: String { placeID }
}
