//
//  GooglePlaceSearchService.swift
//  Dash
//
//  The Google Places SDK for iOS implementation of `PlaceSearchService`.
//
//  This is the ONLY file in the Map feature that imports GooglePlaces. Every GMS
//  type stays private to this file; callers see only `PlaceSuggestion` /
//  `Destination` / `PlaceSearchError`.
//
//  Autocomplete + Place Details (New). Requires the "Places API (New)" enabled on
//  the Google Cloud project and `GooglePlacesConfiguration.bootstrap()` to have
//  run at launch (see Configuration/). A single `GMSAutocompleteSessionToken`
//  groups a run of keystrokes plus the final details fetch into one billing
//  session; it is minted lazily and discarded after `details(for:)`.
//

import CoreLocation
import Foundation
import GooglePlaces

@MainActor
final class GooglePlaceSearchService: PlaceSearchService {

    /// Radius (metres) for autocomplete location bias around the vehicle.
    private static let biasRadiusMeters: CLLocationDistance = 30_000

    private let client: GMSPlacesClient
    private var sessionToken: GMSAutocompleteSessionToken?

    init(client: GMSPlacesClient = .shared()) {
        self.client = client
    }

    func suggestions(matching query: String, near origin: MapCoordinate?) async throws -> [PlaceSuggestion] {
        let token = currentSessionToken()

        let filter = GMSAutocompleteFilter()
        if let origin {
            let coordinate = CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
            filter.locationBias = GMSPlaceCircularLocationOption(coordinate, Self.biasRadiusMeters)
            // Setting `origin` (not just the bias) is what makes the SDK populate
            // `distanceMeters` on each suggestion — the trailing "1.2 km" label.
            filter.origin = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        }

        let request = GMSAutocompleteRequest(query: query)
        request.filter = filter
        request.sessionToken = token

        let results: [GMSAutocompleteSuggestion]
        do {
            results = try await withCheckedThrowingContinuation { continuation in
                client.fetchAutocompleteSuggestions(from: request) { suggestions, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: suggestions ?? [])
                    }
                }
            }
        } catch {
            throw PlaceSearchError.unavailable
        }

        return results.compactMap(Self.mapSuggestion)
    }

    func details(for placeID: String) async throws -> Destination {
        // A details fetch closes the billing session; the next keystroke run
        // starts a fresh one.
        let token = sessionToken
        sessionToken = nil

        let properties: [String] = [
            GMSPlaceProperty.name.rawValue,
            GMSPlaceProperty.formattedAddress.rawValue,
            GMSPlaceProperty.coordinate.rawValue,
            GMSPlaceProperty.placeID.rawValue,
        ]
        let request = GMSFetchPlaceRequest(
            placeID: placeID,
            placeProperties: properties,
            sessionToken: token
        )

        let place: GMSPlace
        do {
            place = try await withCheckedThrowingContinuation { continuation in
                client.fetchPlace(with: request) { place, error in
                    if let place {
                        continuation.resume(returning: place)
                    } else {
                        continuation.resume(throwing: error ?? PlaceSearchError.placeNotFound)
                    }
                }
            }
        } catch let error as PlaceSearchError {
            throw error
        } catch {
            throw PlaceSearchError.unavailable
        }

        let coordinate = place.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            throw PlaceSearchError.placeNotFound
        }

        return Destination(
            placeID: place.placeID ?? placeID,
            name: place.name ?? "",
            address: place.formattedAddress,
            coordinate: MapCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }

    // MARK: - Private

    private func currentSessionToken() -> GMSAutocompleteSessionToken {
        if let sessionToken { return sessionToken }
        let token = GMSAutocompleteSessionToken()
        sessionToken = token
        return token
    }

    private static func mapSuggestion(_ suggestion: GMSAutocompleteSuggestion) -> PlaceSuggestion? {
        guard let place = suggestion.placeSuggestion else { return nil }

        let primary = place.attributedPrimaryText.string
        let full = place.attributedFullText.string
        guard let name = primary.nonBlank ?? full.nonBlank else { return nil }

        return PlaceSuggestion(
            placeID: place.placeID,
            primaryText: name,
            secondaryText: secondaryText(
                primary: primary,
                secondary: place.attributedSecondaryText?.string,
                full: full
            ),
            distanceMeters: place.distanceMeters?.doubleValue,
            category: category(for: place.types)
        )
    }

    // MARK: - Mapping helpers (internal for testing; pure, SDK-free signatures)

    /// The supporting/location line for a suggestion. Prefers the SDK's own
    /// secondary text; if that's blank, falls back to the "…, Area, City" tail of
    /// the full text (which the SDK usually populates as "Name, Area, City").
    nonisolated static func secondaryText(primary: String?, secondary: String?, full: String?) -> String? {
        if let secondary = secondary?.nonBlank {
            return secondary
        }
        if let primary = primary?.nonBlank, let full = full?.nonBlank, primary != full {
            return context(strippingPrefix: primary, from: full)
        }
        return nil
    }

    /// The "…, Area, City" tail of `fullText` once its leading `prefix` (the
    /// place name) is removed. Returns `fullText` unchanged if it doesn't start
    /// with `prefix`.
    nonisolated static func context(strippingPrefix prefix: String, from fullText: String) -> String? {
        guard fullText.hasPrefix(prefix) else { return fullText.nonBlank }
        let tail = fullText.dropFirst(prefix.count).drop { $0 == "," || $0 == " " }
        return String(tail).nonBlank
    }

    /// Maps a Google Places "types" array to a coarse `PlaceCategory` for the
    /// result-row glyph. First (most specific) bucket wins.
    nonisolated static func category(for types: [String]) -> PlaceCategory {
        let types = Set(types)
        func any(_ candidates: String...) -> Bool { !types.isDisjoint(with: candidates) }

        if any("cafe", "coffee_shop") { return .cafe }
        if any("restaurant", "bar", "bakery", "meal_takeaway", "meal_delivery", "food") { return .food }
        if any("store", "shopping_mall", "supermarket", "department_store", "clothing_store",
               "convenience_store", "book_store", "electronics_store", "hardware_store") { return .shopping }
        if any("gas_station") { return .fuel }
        if any("lodging", "hotel", "motel", "resort_hotel") { return .lodging }
        if any("airport", "train_station", "transit_station", "subway_station",
               "bus_station", "light_rail_station") { return .transit }
        if any("tourist_attraction", "museum", "park", "art_gallery", "stadium",
               "place_of_worship", "amusement_park", "zoo") { return .landmark }
        if any("locality", "sublocality", "neighborhood", "postal_code", "route",
               "street_address", "administrative_area_level_1", "administrative_area_level_2",
               "administrative_area_level_3") { return .geographic }
        return .place
    }
}

private extension String {
    /// `self` trimmed, or `nil` when it's empty / whitespace only.
    nonisolated var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
