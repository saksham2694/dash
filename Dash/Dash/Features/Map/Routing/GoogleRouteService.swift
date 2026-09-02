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
//  Cost (spec §5): "Compute Routes" is billed per request. Callers request a
//  route once per trip, plus at most one manual "Refresh Route" (M4.5) — never
//  on a timer. `computeAlternativeRoutes` does not change the pricing tier.
//

import Foundation

@MainActor
final class GoogleRouteService: RouteService {

    /// `computeRoutes` endpoint. `directions/v2:computeRoutes` is a custom verb.
    nonisolated static let endpoint = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!

    /// Only the fields the app actually reads — keeps the response minimal.
    /// The `routes.legs.steps.*` fields (M4.3) carry the turn-by-turn maneuvers;
    /// requesting them moves the call to the Routes "Advanced" SKU, still well
    /// inside the free tier for one user calling once per trip (spec §5).
    nonisolated static let fieldMask = [
        "routes.distanceMeters",
        "routes.duration",
        "routes.polyline.encodedPolyline",
        "routes.legs.steps.distanceMeters",
        "routes.legs.steps.staticDuration",
        "routes.legs.steps.startLocation",
        "routes.legs.steps.endLocation",
        "routes.legs.steps.polyline.encodedPolyline",
        "routes.legs.steps.navigationInstruction",
    ].joined(separator: ",")

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

    func routes(from origin: MapCoordinate, to destination: MapCoordinate) async throws -> [Route] {
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

        return try Self.parseRoutes(from: data)
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
            // Deliberately traffic-*unaware* (spec §5 cost) — alternatives are a
            // separate flag and do not change the pricing tier.
            "routingPreference": "TRAFFIC_UNAWARE",
            "computeAlternativeRoutes": true,
            "polylineEncoding": "ENCODED_POLYLINE",
        ]
        request.httpBody = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return request
    }

    // MARK: - Response mapping (pure; internal for testing)

    /// Translate a `computeRoutes` response body into one or more `Route`s
    /// (M4.5) — response order preserved, `[0]` recommended, each keyed
    /// `"route-<index>"`. Routes with no usable geometry are dropped; throws
    /// `RouteError.noRoute` when none survive or the body can't be decoded.
    nonisolated static func parseRoutes(from data: Data) throws -> [Route] {
        let decoded: ComputeRoutesResponse
        do {
            decoded = try JSONDecoder().decode(ComputeRoutesResponse.self, from: data)
        } catch {
            throw RouteError.noRoute
        }

        guard let dtos = decoded.routes, !dtos.isEmpty else { throw RouteError.noRoute }

        let routes: [Route] = dtos.enumerated().compactMap { index, dto in
            guard let encoded = dto.polyline?.encodedPolyline else { return nil }
            let coordinates = GooglePolyline.decode(encoded)
            guard coordinates.count >= 2 else { return nil }
            return Route(
                id: "route-\(index)",
                polyline: coordinates,
                distanceMeters: dto.distanceMeters ?? 0,
                duration: Self.duration(from: dto.duration) ?? .zero,
                steps: Self.steps(from: dto.legs)
            )
        }

        guard !routes.isEmpty else { throw RouteError.noRoute }
        return routes
    }

    /// Translate the Routes API's `legs[].steps[]` into SDK-neutral `RouteStep`s
    /// (M4.3). Steps with no usable geometry are dropped; the result is `[]` when
    /// the response carries no step data (still a valid `Route` — the overview
    /// polyline stands on its own).
    private nonisolated static func steps(from legs: [ComputeRoutesResponse.LegDTO]?) -> [RouteStep] {
        guard let legs else { return [] }
        return legs.flatMap { $0.steps ?? [] }.compactMap(Self.step(from:))
    }

    private nonisolated static func step(from dto: ComputeRoutesResponse.StepDTO) -> RouteStep? {
        let start = dto.startLocation?.latLng?.coordinate
        let end = dto.endLocation?.latLng?.coordinate

        var polyline = dto.polyline?.encodedPolyline.map(GooglePolyline.decode) ?? []
        if polyline.count < 2 {
            polyline = [start, end].compactMap { $0 }
        }
        guard let maneuverPoint = start ?? polyline.first, polyline.count >= 2 else { return nil }

        let instruction = dto.navigationInstruction?.instructions ?? ""
        return RouteStep(
            maneuver: Self.maneuverType(from: dto.navigationInstruction?.maneuver),
            instruction: instruction,
            roadName: Self.roadName(from: instruction),
            maneuverPoint: maneuverPoint,
            polyline: polyline,
            distanceMeters: dto.distanceMeters ?? RouteGeometry.length(polyline)
        )
    }

    /// Map a Google `Maneuver` enum string onto the SDK-neutral `ManeuverType`.
    /// This is the one place Google's maneuver vocabulary is known.
    nonisolated static func maneuverType(from googleManeuver: String?) -> ManeuverType {
        switch googleManeuver {
        case "DEPART":              return .depart
        case "TURN_LEFT":           return .turnLeft
        case "TURN_RIGHT":          return .turnRight
        case "TURN_SLIGHT_LEFT":    return .turnSlightLeft
        case "TURN_SLIGHT_RIGHT":   return .turnSlightRight
        case "TURN_SHARP_LEFT":     return .turnSharpLeft
        case "TURN_SHARP_RIGHT":    return .turnSharpRight
        case "UTURN_LEFT", "UTURN_RIGHT": return .uTurn
        case "STRAIGHT":            return .straight
        case "RAMP_LEFT":           return .rampLeft
        case "RAMP_RIGHT":          return .rampRight
        case "MERGE":               return .merge
        case "FORK_LEFT":           return .forkLeft
        case "FORK_RIGHT":          return .forkRight
        case "ROUNDABOUT_LEFT", "ROUNDABOUT_RIGHT": return .roundabout
        case "NAME_CHANGE":         return .nameChange
        case "FERRY", "FERRY_TRAIN": return .straight
        default:                    return .unknown
        }
    }

    /// Best-effort road name from a Routes instruction string ("Turn right onto
    /// MG Road" → "MG Road"). Google gives no dedicated field, so this parses the
    /// text — kept here so the heuristic never leaks into the neutral model.
    nonisolated static func roadName(from instruction: String) -> String? {
        for marker in [" onto ", " on to ", " toward ", " on "] {
            if let range = instruction.range(of: marker, options: [.caseInsensitive, .backwards]) {
                let tail = instruction[range.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Drop a trailing "toward X" clause if one slipped through.
                let name = tail.components(separatedBy: " toward ").first ?? tail
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        return nil
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
        var legs: [LegDTO]?
    }

    struct LegDTO: Decodable {
        var steps: [StepDTO]?
    }

    struct StepDTO: Decodable {
        var distanceMeters: Double?
        var staticDuration: String?
        var polyline: PolylineDTO?
        var startLocation: LocationDTO?
        var endLocation: LocationDTO?
        var navigationInstruction: NavigationInstructionDTO?
    }

    struct NavigationInstructionDTO: Decodable {
        var maneuver: String?
        var instructions: String?
    }

    struct LocationDTO: Decodable {
        var latLng: LatLngDTO?
    }

    struct LatLngDTO: Decodable {
        var latitude: Double?
        var longitude: Double?

        var coordinate: MapCoordinate? {
            guard let latitude, let longitude else { return nil }
            return MapCoordinate(latitude: latitude, longitude: longitude)
        }
    }

    struct PolylineDTO: Decodable {
        var encodedPolyline: String?
    }
}
