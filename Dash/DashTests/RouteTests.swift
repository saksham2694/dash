//
//  RouteTests.swift
//  DashTests
//
//  M3 routing: the SDK-neutral `Route` model, the encoded-polyline decoder,
//  Google Routes request construction + response mapping (with canned data — no
//  live API), `RouteViewModel` orchestration, and how `MapViewModel` renders a
//  route into `MapContent`. No SDK, no networking.
//

import Foundation
import Testing
@testable import Dash
import DashShared

// MARK: - Helpers

@MainActor
private final class StubRouteService: RouteService {
    var result: Result<Route, Error> = .failure(RouteError.unavailable)
    private(set) var calls: [(origin: MapCoordinate, destination: MapCoordinate)] = []

    func route(from origin: MapCoordinate, to destination: MapCoordinate) async throws -> Route {
        calls.append((origin, destination))
        return try result.get()
    }
}

private func sampleRoute(
    _ coordinates: [MapCoordinate] = [
        MapCoordinate(latitude: 12.90, longitude: 77.60),
        MapCoordinate(latitude: 12.95, longitude: 77.62),
        MapCoordinate(latitude: 13.00, longitude: 77.65),
    ],
    distanceMeters: Double = 12_345,
    duration: Duration = .seconds(900)
) -> Route {
    Route(polyline: coordinates, distanceMeters: distanceMeters, duration: duration)
}

private func destination(
    _ id: String = "dest-1",
    lat: Double = 13.0,
    lon: Double = 77.65
) -> Destination {
    Destination(placeID: id, name: "Airport", address: "Devanahalli",
                coordinate: MapCoordinate(latitude: lat, longitude: lon))
}

private func almostEqual(_ a: MapCoordinate, _ b: MapCoordinate, tolerance: Double = 1e-5) -> Bool {
    abs(a.latitude - b.latitude) <= tolerance && abs(a.longitude - b.longitude) <= tolerance
}

// MARK: - Route domain model

@Suite("Route model")
struct RouteModelTests {

    @Test("is equatable by geometry, distance and duration")
    func equatable() {
        let a = sampleRoute()
        #expect(a == sampleRoute())
        #expect(a != sampleRoute(distanceMeters: 999))
        #expect(a != sampleRoute(duration: .seconds(1)))
        #expect(a != sampleRoute([MapCoordinate(latitude: 0, longitude: 0)]))
    }

    @Test("carries distance and duration for later milestones")
    func retainsMetrics() {
        let route = sampleRoute(distanceMeters: 4_200, duration: .seconds(360))
        #expect(route.distanceMeters == 4_200)
        #expect(route.duration == .seconds(360))
    }
}

// MARK: - Encoded polyline decoder

@Suite("GooglePolyline")
struct GooglePolylineTests {

    @Test("decodes the reference polyline from Google's algorithm spec")
    func referenceExample() {
        let coords = GooglePolyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(coords.count == 3)
        #expect(almostEqual(coords[0], MapCoordinate(latitude: 38.5, longitude: -120.2)))
        #expect(almostEqual(coords[1], MapCoordinate(latitude: 40.7, longitude: -120.95)))
        #expect(almostEqual(coords[2], MapCoordinate(latitude: 43.252, longitude: -126.453)))
    }

    @Test("an empty string decodes to no coordinates")
    func empty() {
        #expect(GooglePolyline.decode("") == [])
    }

    @Test("a truncated string stops cleanly instead of crashing")
    func truncated() {
        // First point only, second delta pair cut short.
        let coords = GooglePolyline.decode("_p~iF~ps|U_ulL")
        #expect(coords.count == 1)
    }
}

// MARK: - Google Routes request / response mapping

@Suite("GoogleRouteService mapping")
struct GoogleRouteServiceMappingTests {

    @Test("builds a POST to the Routes endpoint with the key, field mask and a DRIVE body")
    func requestConstruction() throws {
        let request = GoogleRouteService.makeRequest(
            from: MapCoordinate(latitude: 12.9, longitude: 77.6),
            to: MapCoordinate(latitude: 13.1, longitude: 77.7),
            apiKey: "TEST-KEY"
        )

        #expect(request.url == GoogleRouteService.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Api-Key") == "TEST-KEY")
        #expect(request.value(forHTTPHeaderField: "X-Goog-FieldMask") == GoogleRouteService.fieldMask)

        let httpBody = try #require(request.httpBody)
        let body = try #require(
            try JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
        )
        #expect(body["travelMode"] as? String == "DRIVE")
        #expect(body["polylineEncoding"] as? String == "ENCODED_POLYLINE")

        let originLatLng = (((body["origin"] as? [String: Any])?["location"] as? [String: Any])?["latLng"] as? [String: Any])
        #expect(originLatLng?["latitude"] as? Double == 12.9)
        #expect(originLatLng?["longitude"] as? Double == 77.6)
        let destLatLng = (((body["destination"] as? [String: Any])?["location"] as? [String: Any])?["latLng"] as? [String: Any])
        #expect(destLatLng?["latitude"] as? Double == 13.1)
        #expect(destLatLng?["longitude"] as? Double == 77.7)
    }

    @Test("sends the iOS bundle identifier so an app-restricted key is accepted")
    func requestCarriesBundleIdentifier() {
        let request = GoogleRouteService.makeRequest(
            from: MapCoordinate(latitude: 12.9, longitude: 77.6),
            to: MapCoordinate(latitude: 13.1, longitude: 77.7),
            apiKey: "TEST-KEY",
            bundleID: "com.sakshamsharma.Dash"
        )
        #expect(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier") == "com.sakshamsharma.Dash")
        // The key still goes in its own header, unchanged.
        #expect(request.value(forHTTPHeaderField: "X-Goog-Api-Key") == "TEST-KEY")
    }

    @Test("maps a successful Routes response to a Route")
    func successMapping() throws {
        let json = Data(#"""
        {"routes":[{"distanceMeters":12345,"duration":"600s","polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC_mqNvxq`@"}}]}
        """#.utf8)

        let route = try GoogleRouteService.parseRoute(from: json)
        #expect(route.distanceMeters == 12_345)
        #expect(route.duration == .seconds(600))
        #expect(route.polyline.count == 3)
        #expect(almostEqual(route.polyline[0], MapCoordinate(latitude: 38.5, longitude: -120.2)))
    }

    @Test("a fractional-second duration parses")
    func fractionalDuration() {
        #expect(GoogleRouteService.duration(from: "12.5s") == .seconds(12.5))
        #expect(GoogleRouteService.duration(from: "600s") == .seconds(600))
        #expect(GoogleRouteService.duration(from: "nonsense") == nil)
        #expect(GoogleRouteService.duration(from: nil) == nil)
    }

    @Test("an empty routes array is a no-route failure")
    func emptyRoutes() {
        #expect(throws: RouteError.noRoute) {
            try GoogleRouteService.parseRoute(from: Data(#"{"routes":[]}"#.utf8))
        }
    }

    @Test("a route with a degenerate (single-point) polyline is a no-route failure")
    func degeneratePolyline() {
        let json = Data(#"{"routes":[{"distanceMeters":0,"duration":"0s","polyline":{"encodedPolyline":"_p~iF~ps|U"}}]}"#.utf8)
        #expect(throws: RouteError.noRoute) {
            try GoogleRouteService.parseRoute(from: json)
        }
    }

    @Test("malformed JSON is a no-route failure, not a crash")
    func malformedJSON() {
        #expect(throws: RouteError.noRoute) {
            try GoogleRouteService.parseRoute(from: Data("not json".utf8))
        }
    }
}

// MARK: - GoogleRouteService end-to-end (mocked transport, no live API)

@MainActor
@Suite("GoogleRouteService")
struct GoogleRouteServiceTests {

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: GoogleRouteService.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private let okBody = Data(#"""
    {"routes":[{"distanceMeters":50,"duration":"30s","polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC"}}]}
    """#.utf8)

    @Test("a 200 response yields a mapped Route")
    func success() async throws {
        let service = GoogleRouteService(
            apiKey: { "KEY" },
            fetch: { _ in (self.okBody, self.response(200)) }
        )
        let route = try await service.route(
            from: MapCoordinate(latitude: 1, longitude: 1),
            to: MapCoordinate(latitude: 2, longitude: 2)
        )
        #expect(route.distanceMeters == 50)
        #expect(route.duration == .seconds(30))
        #expect(route.polyline.count == 2)
    }

    @Test("a 403 (Routes API not enabled / key not authorised) surfaces as .unavailable")
    func forbidden() async {
        let service = GoogleRouteService(
            apiKey: { "KEY" },
            fetch: { _ in (Data(), self.response(403)) }
        )
        await #expect(throws: RouteError.unavailable) {
            _ = try await service.route(from: MapCoordinate(latitude: 1, longitude: 1),
                                        to: MapCoordinate(latitude: 2, longitude: 2))
        }
    }

    @Test("a transport error surfaces as .unavailable")
    func transportError() async {
        struct Boom: Error {}
        let service = GoogleRouteService(apiKey: { "KEY" }, fetch: { _ in throw Boom() })
        await #expect(throws: RouteError.unavailable) {
            _ = try await service.route(from: MapCoordinate(latitude: 1, longitude: 1),
                                        to: MapCoordinate(latitude: 2, longitude: 2))
        }
    }

    @Test("a missing API key fails as .unavailable without a network call")
    func missingKey() async {
        var fetched = false
        let service = GoogleRouteService(
            apiKey: { nil },
            fetch: { _ in fetched = true; return (Data(), self.response(200)) }
        )
        await #expect(throws: RouteError.unavailable) {
            _ = try await service.route(from: MapCoordinate(latitude: 1, longitude: 1),
                                        to: MapCoordinate(latitude: 2, longitude: 2))
        }
        #expect(fetched == false)
    }
}

// MARK: - RouteViewModel orchestration

@MainActor
@Suite("RouteViewModel")
struct RouteViewModelTests {

    @Test("selecting a destination with an origin requests a route and loads it")
    func loadsRoute() async {
        let service = StubRouteService()
        service.result = .success(sampleRoute())
        let vm = RouteViewModel(service: service)

        vm.requestRoute(to: destination(), from: MapCoordinate(latitude: 12.9, longitude: 77.6))
        #expect(vm.state == .loading)
        await vm.currentTask?.value

        #expect(vm.state == .loaded(sampleRoute()))
        #expect(service.calls.count == 1)
        #expect(service.calls.first?.origin == MapCoordinate(latitude: 12.9, longitude: 77.6))
        #expect(service.calls.first?.destination == destination().coordinate)
    }

    @Test("no current location yields a meaningful state and never calls the service")
    func noLocation() {
        let service = StubRouteService()
        let vm = RouteViewModel(service: service)

        vm.requestRoute(to: destination(), from: nil)

        #expect(vm.state == .noCurrentLocation)
        #expect(service.calls.isEmpty)
        #expect(vm.currentTask == nil)
    }

    @Test("a routing failure surfaces the RouteError")
    func failure() async {
        let service = StubRouteService()
        service.result = .failure(RouteError.noRoute)
        let vm = RouteViewModel(service: service)

        vm.requestRoute(to: destination(), from: MapCoordinate(latitude: 1, longitude: 1))
        await vm.currentTask?.value

        #expect(vm.state == .failed(.noRoute))
    }

    @Test("an unexpected error is normalised to .failed(.unavailable)")
    func unexpectedError() async {
        struct Boom: Error {}
        let service = StubRouteService()
        service.result = .failure(Boom())
        let vm = RouteViewModel(service: service)

        vm.requestRoute(to: destination(), from: MapCoordinate(latitude: 1, longitude: 1))
        await vm.currentTask?.value

        #expect(vm.state == .failed(.unavailable))
    }

    @Test("clearing the destination returns to idle without a request")
    func clear() {
        let service = StubRouteService()
        let vm = RouteViewModel(service: service)

        vm.requestRoute(to: nil, from: nil)

        #expect(vm.state == .idle)
        #expect(service.calls.isEmpty)
    }

    @Test("a new request cancels the one in flight")
    func cancelsInFlight() async {
        let service = StubRouteService()
        service.result = .success(sampleRoute())
        let vm = RouteViewModel(service: service)

        vm.requestRoute(to: destination("a"), from: MapCoordinate(latitude: 1, longitude: 1))
        let first = vm.currentTask
        vm.requestRoute(to: destination("b"), from: MapCoordinate(latitude: 2, longitude: 2))

        #expect(first?.isCancelled == true)
        await vm.currentTask?.value
        #expect(vm.state == .loaded(sampleRoute()))
    }
}

// MARK: - Route rendering in MapViewModel

@MainActor
@Suite("MapViewModel route")
struct MapViewModelRouteTests {

    private func packet(_ lat: Double, _ lon: Double) -> LocationPacket {
        LocationPacket(latitude: lat, longitude: lon, speed: 0, heading: -1,
                       timestamp: Date(timeIntervalSince1970: 1_756_700_000))
    }

    @Test("setRoute draws exactly one polyline keyed by the route id")
    func setRouteDrawsPolyline() {
        let vm = MapViewModel()
        let coords = [
            MapCoordinate(latitude: 12.9, longitude: 77.6),
            MapCoordinate(latitude: 13.0, longitude: 77.65),
        ]
        vm.setRoute(Route(polyline: coords, distanceMeters: 100, duration: .seconds(60)))

        #expect(vm.content.polylines == [
            MapPolyline(id: MapViewModel.routePolylineID, coordinates: coords)
        ])
    }

    @Test("setRoute(nil) clears the route line")
    func clearRoute() {
        let vm = MapViewModel()
        vm.setRoute(Route(polyline: [MapCoordinate(latitude: 1, longitude: 1),
                                     MapCoordinate(latitude: 2, longitude: 2)],
                          distanceMeters: 1, duration: .zero))
        vm.setRoute(nil)
        #expect(vm.content.polylines.isEmpty)
    }

    @Test("outside destination preview, setRoute never moves the camera")
    func routeDoesNotMoveCameraWhenCruising() {
        let vm = MapViewModel()
        vm.update(with: packet(5, 5)) // cruising, no destination
        let camera = vm.content.camera

        vm.setRoute(Route(polyline: [MapCoordinate(latitude: 40, longitude: 40),
                                     MapCoordinate(latitude: 41, longitude: 41)],
                          distanceMeters: 1, duration: .zero))

        #expect(vm.mode == .cruising)
        #expect(vm.content.camera == camera)
    }

    @Test("in destination preview, a loaded route re-fits the camera around the whole route")
    func routeReframesPreviewCamera() {
        let vm = MapViewModel()
        vm.update(with: packet(12.0, 77.0))
        vm.setDestination(destination()) // 13.2, 77.7

        // A route that bows west of the straight vehicle→destination line.
        let routeCoords = [
            MapCoordinate(latitude: 12.0, longitude: 77.0),
            MapCoordinate(latitude: 12.6, longitude: 76.5),
            MapCoordinate(latitude: 13.2, longitude: 77.7),
        ]
        vm.setRoute(Route(polyline: routeCoords, distanceMeters: 100, duration: .seconds(60)))

        let expected = MapCoordinateBounds(
            [MapCoordinate(latitude: 12.0, longitude: 77.0),
             MapCoordinate(latitude: 13.2, longitude: 77.7)] + routeCoords
        )!
        #expect(vm.content.camera == .fit(expected, padding: MapViewModel.previewPadding))
        // The bow actually widened the box past the vehicle↔destination line.
        #expect(expected.southWest.longitude == 76.5)
    }

    @Test("clearing the route in preview re-fits to just vehicle + destination")
    func clearRouteReframesPreview() {
        let vm = MapViewModel()
        vm.update(with: packet(12.0, 77.0))
        vm.setDestination(destination())
        vm.setRoute(Route(polyline: [MapCoordinate(latitude: 12.0, longitude: 76.0),
                                     MapCoordinate(latitude: 13.2, longitude: 77.7)],
                          distanceMeters: 1, duration: .zero))

        vm.setRoute(nil)

        let expected = MapCoordinateBounds([
            MapCoordinate(latitude: 12.0, longitude: 77.0),
            MapCoordinate(latitude: 13.2, longitude: 77.7),
        ])!
        #expect(vm.content.camera == .fit(expected, padding: MapViewModel.previewPadding))
    }

    @Test("while previewing a route, a later fix moves the vehicle but not the camera")
    func routePreviewCameraStaysWhileVehicleMoves() {
        let vm = MapViewModel()
        vm.update(with: packet(12.0, 77.0))
        vm.setDestination(destination())
        vm.setRoute(Route(polyline: [MapCoordinate(latitude: 12.0, longitude: 77.0),
                                     MapCoordinate(latitude: 13.2, longitude: 77.7)],
                          distanceMeters: 1, duration: .zero))
        let framed = vm.content.camera

        vm.update(with: packet(12.5, 77.3))

        #expect(vm.content.vehicle.coordinate == MapCoordinate(latitude: 12.5, longitude: 77.3))
        #expect(vm.content.camera == framed)
    }

    @Test("choosing a new destination clears the previous route until it is recomputed")
    func newDestinationClearsRoute() {
        let vm = MapViewModel()
        vm.setRoute(Route(polyline: [MapCoordinate(latitude: 1, longitude: 1),
                                     MapCoordinate(latitude: 2, longitude: 2)],
                          distanceMeters: 1, duration: .zero))

        vm.setDestination(destination())

        #expect(vm.content.polylines.isEmpty)
        #expect(vm.route == nil)
        #expect(vm.content.markers.count == 1) // M2 pin still drops
    }

    private func destination() -> Destination {
        Destination(placeID: "d", name: "X", address: nil,
                    coordinate: MapCoordinate(latitude: 13.2, longitude: 77.7))
    }
}
