//
//  GoogleRouteService.swift
//  Dash
//
//  The Google Routes API implementation of `RouteService` (M3).
//
//  The Routes API is a plain REST endpoint, not part of the Maps SDK — so this
//  file imports only Foundation and names no GMS types. It reuses the existing
//  build-injected key via `GoogleMapsConfiguration.apiKey`; nothing is
//  hard-coded.
//
//  Requires the **Routes API** to be enabled on the Google Cloud project and the
//  key's API restrictions to allow it — a manual console step, distinct from the
//  Maps SDK and Places API (New). The key also carries an iOS *application*
//  restriction (an allow-list of bundle IDs); the Maps / Places SDKs send the
//  bundle ID automatically, and this REST call does the same via the
//  `X-Ios-Bundle-Identifier` header so the same restricted key works here too.
//  A 403 from the endpoint surfaces as `RouteError.unavailable`.
//
//  Cost (spec §5): "Compute Routes" is billed per request. Callers must request
//  a route once per trip — never on a timer.
//

import Foundation

@MainActor
final class GoogleRouteService: RouteService {

    /// `computeRoutes` endpoint. `directions/v2:computeRoutes` is a custom verb.
    nonisolated static let endpoint = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!

    /// Only the fields the app actually reads — keeps the response (and billing
    /// SKU) minimal.
    nonisolated static let fieldMask = "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline"

    typealias Fetch = (URLRequest) async throws -> (Data, URLResponse)

    private let apiKey: () -> String?
    private let fetch: Fetch

    init(
        apiKey: @escaping () -> String? = { GoogleMapsConfiguration.apiKey },
        fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }
    ) {
        self.apiKey = apiKey
        self.fetch = fetch
    }

    func route(from origin: MapCoordinate, to destination: MapCoordinate) async throws -> Route {
        guard let key = apiKey() else { throw RouteError.unavailable }

        let request = Self.makeRequest(from: origin, to: destination, apiKey: key)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetch(request)
        } catch {
            throw RouteError.unavailable
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // 403 = Routes API not enabled / key not authorised; 4xx/5xx = other.
            throw RouteError.unavailable
        }

        return try Self.parseRoute(from: data)
    }

    // MARK: - Request construction (pure; internal for testing)

    nonisolated static func makeRequest(
        from origin: MapCoordinate,
        to destination: MapCoordinate,
        apiKey: String,
        bundleID: String? = nil
    ) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        // Satisfies the API key's iOS application restriction on a REST call.
        if let bundleID = bundleID ?? Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        let body: [String: Any] = [
            "origin": ["location": ["latLng": ["latitude": origin.latitude, "longitude": origin.longitude]]],
            "destination": ["location": ["latLng": ["latitude": destination.latitude, "longitude": destination.longitude]]],
            "travelMode": "DRIVE",
            "routingPreference": "TRAFFIC_UNAWARE",
            "polylineEncoding": "ENCODED_POLYLINE",
        ]
        request.httpBody = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return request
    }

    // MARK: - Response mapping (pure; internal for testing)

    /// Translate a `computeRoutes` response body into a `Route`. Throws
    /// `RouteError.noRoute` when the response carries no usable route.
    nonisolated static func parseRoute(from data: Data) throws -> Route {
        let decoded: ComputeRoutesResponse
        do {
            decoded = try JSONDecoder().decode(ComputeRoutesResponse.self, from: data)
        } catch {
            throw RouteError.noRoute
        }

        guard
            let first = decoded.routes?.first,
            let encoded = first.polyline?.encodedPolyline
        else {
            throw RouteError.noRoute
        }

        let coordinates = GooglePolyline.decode(encoded)
        guard coordinates.count >= 2 else { throw RouteError.noRoute }

        return Route(
            polyline: coordinates,
            distanceMeters: first.distanceMeters ?? 0,
            duration: Self.duration(from: first.duration) ?? .zero
        )
    }

    /// Parse a protobuf-style duration string ("600s", "12.5s") into `Duration`.
    nonisolated static func duration(from string: String?) -> Duration? {
        guard let string, string.hasSuffix("s"),
              let seconds = Double(string.dropLast())
        else { return nil }
        return .seconds(seconds)
    }
}

// MARK: - Response DTOs (private to this file; never leave it)

private nonisolated struct ComputeRoutesResponse: Decodable {
    var routes: [RouteDTO]?

    struct RouteDTO: Decodable {
        var distanceMeters: Double?
        var duration: String?
        var polyline: PolylineDTO?
    }

    struct PolylineDTO: Decodable {
        var encodedPolyline: String?
    }
}
