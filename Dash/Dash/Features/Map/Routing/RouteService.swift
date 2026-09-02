//
//  RouteService.swift
//  Dash
//
//  The provider-neutral routing abstraction (M3). A *separate* protocol from
//  `MapProvider` and `PlaceSearchService` — route computation is neither a
//  rendering concern nor a search concern, and Apple's path (MKDirections) is
//  unrelated to Google's Routes API. `MapProvider` never grows a `route(...)`
//  method.
//
//  Implementations: `GoogleRouteService` (Google Routes API) today; an Apple one
//  later. Callers depend only on this protocol and on `Route` / `RouteError`.
//
//  M4.5: `routes(...)` returns the recommended route plus any alternatives the
//  provider offers — first element is the recommended one, and the array is
//  never empty on success (the provider throws `.noRoute` instead).
//

import Foundation

@MainActor
protocol RouteService {

    /// Compute one or more driving routes between two points — `[0]` is the
    /// recommended route, the rest are alternatives. Never empty on success.
    /// Throws `RouteError` (never a provider error type) on failure.
    func routes(from origin: MapCoordinate, to destination: MapCoordinate) async throws -> [Route]
}

/// Failure surfaced to the routing UI. Coarse on purpose — the UI only needs to
/// tell "no route" from "couldn't reach the service".
enum RouteError: Error, Equatable {

    /// The request succeeded but no route exists between the two points.
    case noRoute

    /// The provider isn't configured / reachable — no API key, offline, or the
    /// Routes API isn't enabled / authorised for the key (HTTP 403).
    case unavailable
}
