//
//  RouteTests.swift
//  DashTests
//
//  M3–M4.5 routing: the SDK-neutral `Route` / `RouteOptions` models, the
//  encoded-polyline decoder, Google Routes request construction + response
//  mapping (with canned data — no live API), `RouteViewModel` orchestration
//  (incl. the M4.5 multi-route + manual-refresh path), and how `MapViewModel`
//  renders routes into `MapContent`. No SDK, no networking.
//

import Foundation
import Testing
@testable import Dash
import DashShared

// MARK: - Helpers

@MainActor
private final class StubRouteService: RouteService {
    var result: Result<[Route], Error> = .failure(RouteError.unavailable)
    private(set) var calls: [(origin: MapCoordinate, destination: MapCoordinate)] = []

    func routes(from origin: MapCoordinate, to destination: MapCoordinate) async throws -> [Route] {
        calls.append((origin, destination))
        return try result.get()
    }
}

private func sampleRoute(
    id: String = "route",
    _ coordinates: [MapCoordinate] = [
        MapCoordinate(latitude: 12.90, longitude: 77.60),
        MapCoordinate(latitude: 12.95, longitude: 77.62),
        MapCoordinate(latitude: 13.00, longitude: 77.65),
    ],
    distanceMeters: Double = 12_345,
    duration: Duration = .seconds(900)
) -> Route {
    Route(id: id, polyline: coordinates, distanceMeters: distanceMeters, duration: duration)
}

private func options(_ routes: Route...) -> RouteOptions {
    RouteOptions(routes)!
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
        // M4.3: the field mask must ask for the per-step maneuver data.
        #expect(GoogleRouteService.fieldMask.contains("routes.legs.steps.navigationInstruction"))
        #expect(GoogleRouteService.fieldMask.contains("routes.legs.steps.polyline.encodedPolyline"))
        #expect(GoogleRouteService.fieldMask.contains("routes.legs.steps.startLocation"))

        let httpBody = try #require(request.httpBody)
        let body = try #require(
            try JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
        )
        #expect(body["travelMode"] as? String == "DRIVE")
        #expect(body["polylineEncoding"] as? String == "ENCODED_POLYLINE")
        // M4.5: alternatives requested; still traffic-unaware.
        #expect(body["computeAlternativeRoutes"] as? Bool == true)
        #expect(body["routingPreference"] as? String == "TRAFFIC_UNAWARE")

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

    @Test("maps a successful single-route response")
    func successMapping() throws {
        let json = Data(#"""
        {"routes":[{"distanceMeters":12345,"duration":"600s","polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC_mqNvxq`@"}}]}
        """#.utf8)

        let routes = try GoogleRouteService.parseRoutes(from: json)
        #expect(routes.count == 1)
        let route = routes[0]
        #expect(route.id == "route-0")
        #expect(route.distanceMeters == 12_345)
        #expect(route.duration == .seconds(600))
        #expect(route.polyline.count == 3)
        #expect(almostEqual(route.polyline[0], MapCoordinate(latitude: 38.5, longitude: -120.2)))
    }

    @Test("maps every alternative in the response, in order, with stable ids (M4.5)")
    func multipleRoutesMapping() throws {
        let json = Data(#"""
        {"routes":[
          {"distanceMeters":12000,"duration":"1080s","polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC"}},
          {"distanceMeters":14000,"duration":"960s","polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC_mqNvxq`@"}},
          {"distanceMeters":11000,"duration":"1320s","polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC"}}
        ]}
        """#.utf8)

        let routes = try GoogleRouteService.parseRoutes(from: json)
        #expect(routes.count == 3)
        #expect(routes.map(\.id) == ["route-0", "route-1", "route-2"])
        #expect(routes[0].distanceMeters == 12_000)   // response order preserved
        #expect(routes[1].duration == .seconds(960))
        #expect(routes[2].polyline.count == 2)
    }

    @Test("routes with no usable geometry are dropped; a usable one still returns")
    func mixedRoutesDropUnusable() throws {
        let json = Data(#"""
        {"routes":[
          {"distanceMeters":1,"duration":"1s","polyline":{"encodedPolyline":"_p~iF~ps|U"}},
          {"distanceMeters":12000,"duration":"600s","polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC"}}
        ]}
        """#.utf8)
        let routes = try GoogleRouteService.parseRoutes(from: json)
        #expect(routes.count == 1)
        #expect(routes[0].distanceMeters == 12_000)
    }

    @Test("a fractional-second duration parses")
    func fractionalDuration() {
        #expect(GoogleRouteService.duration(from: "12.5s") == .seconds(12.5))
        #expect(GoogleRouteService.duration(from: "600s") == .seconds(600))
        #expect(GoogleRouteService.duration(from: "nonsense") == nil)
        #expect(GoogleRouteService.duration(from: nil) == nil)
    }

    // MARK: - M4.3 step / maneuver parsing

    @Test("parses per-step maneuvers, geometry and road names from the legs")
    func parsesSteps() throws {
        let json = Data(#"""
        {"routes":[{
          "distanceMeters":1000,"duration":"120s",
          "polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC_mqNvxq`@"},
          "legs":[{"steps":[
            {"distanceMeters":400,"staticDuration":"40s",
             "startLocation":{"latLng":{"latitude":38.5,"longitude":-120.2}},
             "endLocation":{"latLng":{"latitude":40.7,"longitude":-120.95}},
             "polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC"},
             "navigationInstruction":{"maneuver":"DEPART","instructions":"Head north on Main Street"}},
            {"distanceMeters":600,"staticDuration":"80s",
             "startLocation":{"latLng":{"latitude":40.7,"longitude":-120.95}},
             "endLocation":{"latLng":{"latitude":40.9,"longitude":-121.0}},
             "polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC"},
             "navigationInstruction":{"maneuver":"TURN_RIGHT","instructions":"Turn right onto Mahatma Gandhi Road"}}
          ]}]
        }]}
        """#.utf8)

        let route = try GoogleRouteService.parseRoutes(from: json)[0]
        #expect(route.polyline.count == 3) // overview polyline unchanged
        #expect(route.steps.count == 2)

        #expect(route.steps[0].maneuver == .depart)
        #expect(route.steps[0].roadName == "Main Street")

        #expect(route.steps[1].maneuver == .turnRight)
        #expect(route.steps[1].roadName == "Mahatma Gandhi Road")
        #expect(route.steps[1].distanceMeters == 600)
        #expect(almostEqual(route.steps[1].maneuverPoint, MapCoordinate(latitude: 40.7, longitude: -120.95)))
        #expect(route.steps[1].polyline.count >= 2)
    }

    @Test("a response with no legs still parses to a valid route with no steps")
    func noStepsIsValid() throws {
        let json = Data(#"{"routes":[{"distanceMeters":50,"duration":"30s","polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC"}}]}"#.utf8)
        let route = try GoogleRouteService.parseRoutes(from: json)[0]
        #expect(route.steps.isEmpty)
        #expect(route.polyline.count == 2)
    }

    @Test("Google maneuver strings map to the neutral ManeuverType")
    func maneuverMapping() {
        #expect(GoogleRouteService.maneuverType(from: "DEPART") == .depart)
        #expect(GoogleRouteService.maneuverType(from: "TURN_LEFT") == .turnLeft)
        #expect(GoogleRouteService.maneuverType(from: "TURN_RIGHT") == .turnRight)
        #expect(GoogleRouteService.maneuverType(from: "TURN_SHARP_LEFT") == .turnSharpLeft)
        #expect(GoogleRouteService.maneuverType(from: "UTURN_LEFT") == .uTurn)
        #expect(GoogleRouteService.maneuverType(from: "UTURN_RIGHT") == .uTurn)
        #expect(GoogleRouteService.maneuverType(from: "ROUNDABOUT_RIGHT") == .roundabout)
        #expect(GoogleRouteService.maneuverType(from: "MERGE") == .merge)
        #expect(GoogleRouteService.maneuverType(from: "STRAIGHT") == .straight)
        #expect(GoogleRouteService.maneuverType(from: "NAME_CHANGE") == .nameChange)
        #expect(GoogleRouteService.maneuverType(from: "SOMETHING_NEW") == .unknown)
        #expect(GoogleRouteService.maneuverType(from: nil) == .unknown)
    }

    @Test("road name is pulled out of the instruction text, best-effort")
    func roadNameExtraction() {
        #expect(GoogleRouteService.roadName(from: "Turn right onto MG Road") == "MG Road")
        #expect(GoogleRouteService.roadName(from: "Continue straight on 5th Avenue") == "5th Avenue")
        #expect(GoogleRouteService.roadName(from: "Merge onto NH-44 toward Hosur") == "NH-44")
        #expect(GoogleRouteService.roadName(from: "Make a U-turn") == nil)
    }

    @Test("an empty routes array is a no-route failure")
    func emptyRoutes() {
        #expect(throws: RouteError.noRoute) {
            try GoogleRouteService.parseRoutes(from: Data(#"{"routes":[]}"#.utf8))
        }
    }

    @Test("a response whose only route has a degenerate polyline is a no-route failure")
    func degeneratePolyline() {
        let json = Data(#"{"routes":[{"distanceMeters":0,"duration":"0s","polyline":{"encodedPolyline":"_p~iF~ps|U"}}]}"#.utf8)
        #expect(throws: RouteError.noRoute) {
            try GoogleRouteService.parseRoutes(from: json)
        }
    }

    @Test("malformed JSON is a no-route failure, not a crash")
    func malformedJSON() {
        #expect(throws: RouteError.noRoute) {
            try GoogleRouteService.parseRoutes(from: Data("not json".utf8))
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

    @Test("a 200 response yields mapped Routes")
    func success() async throws {
        let service = GoogleRouteService(
            apiKey: { "KEY" },
            fetch: { _ in (self.okBody, self.response(200)) }
        )
        let routes = try await service.routes(
            from: MapCoordinate(latitude: 1, longitude: 1),
            to: MapCoordinate(latitude: 2, longitude: 2)
        )
        #expect(routes.count == 1)
        #expect(routes[0].distanceMeters == 50)
        #expect(routes[0].duration == .seconds(30))
        #expect(routes[0].polyline.count == 2)
    }

    @Test("a 403 (Routes API not enabled / key not authorised) surfaces as .unavailable")
    func forbidden() async {
        let service = GoogleRouteService(
            apiKey: { "KEY" },
            fetch: { _ in (Data(), self.response(403)) }
        )
        await #expect(throws: RouteError.unavailable) {
            _ = try await service.routes(from: MapCoordinate(latitude: 1, longitude: 1),
                                         to: MapCoordinate(latitude: 2, longitude: 2))
        }
    }

    @Test("a transport error surfaces as .unavailable")
    func transportError() async {
        struct Boom: Error {}
        let service = GoogleRouteService(apiKey: { "KEY" }, fetch: { _ in throw Boom() })
        await #expect(throws: RouteError.unavailable) {
            _ = try await service.routes(from: MapCoordinate(latitude: 1, longitude: 1),
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
            _ = try await service.routes(from: MapCoordinate(latitude: 1, longitude: 1),
                                         to: MapCoordinate(latitude: 2, longitude: 2))
        }
        #expect(fetched == false)
    }
}

// MARK: - RouteViewModel orchestration

@MainActor
@Suite("RouteViewModel")
struct RouteViewModelTests {

    private func routeSet(_ ids: [String], durations: [Duration]) -> [Route] {
        zip(ids, durations).map { id, duration in
            sampleRoute(id: id, distanceMeters: 10_000, duration: duration)
        }
    }

    @Test("a destination + origin requests routes and loads them, recommended selected")
    func loadsRoutes() async {
        let service = StubRouteService()
        service.result = .success(routeSet(["route-0", "route-1"], durations: [.seconds(1000), .seconds(900)]))
        let vm = RouteViewModel(service: service)

        vm.requestRoutes(to: destination(), from: MapCoordinate(latitude: 12.9, longitude: 77.6))
        #expect(vm.state == .loading)
        await vm.currentTask?.value

        guard case .loaded(let opts) = vm.state else { Issue.record("expected .loaded"); return }
        #expect(opts.routes.count == 2)
        #expect(opts.selected.id == "route-0")   // recommended
        #expect(vm.destination == destination())
        #expect(service.calls.count == 1)
    }

    @Test("a single-route response still loads (fallback)")
    func singleRouteFallback() async {
        let service = StubRouteService()
        service.result = .success([sampleRoute()])
        let vm = RouteViewModel(service: service)

        vm.requestRoutes(to: destination(), from: MapCoordinate(latitude: 1, longitude: 1))
        await vm.currentTask?.value

        guard case .loaded(let opts) = vm.state else { Issue.record("expected .loaded"); return }
        #expect(opts.routes.count == 1)
        #expect(opts.hasAlternatives == false)
    }

    @Test("no current location yields a meaningful state and never calls the service")
    func noLocation() {
        let service = StubRouteService()
        let vm = RouteViewModel(service: service)

        vm.requestRoutes(to: destination(), from: nil)

        #expect(vm.state == .noCurrentLocation)
        #expect(service.calls.isEmpty)
        #expect(vm.currentTask == nil)
    }

    @Test("a routing failure surfaces the RouteError")
    func failure() async {
        let service = StubRouteService()
        service.result = .failure(RouteError.noRoute)
        let vm = RouteViewModel(service: service)

        vm.requestRoutes(to: destination(), from: MapCoordinate(latitude: 1, longitude: 1))
        await vm.currentTask?.value

        #expect(vm.state == .failed(.noRoute))
    }

    @Test("an unexpected error is normalised to .failed(.unavailable)")
    func unexpectedError() async {
        struct Boom: Error {}
        let service = StubRouteService()
        service.result = .failure(Boom())
        let vm = RouteViewModel(service: service)

        vm.requestRoutes(to: destination(), from: MapCoordinate(latitude: 1, longitude: 1))
        await vm.currentTask?.value

        #expect(vm.state == .failed(.unavailable))
    }

    @Test("clearing the destination returns to idle without a request")
    func clear() {
        let service = StubRouteService()
        let vm = RouteViewModel(service: service)

        vm.requestRoutes(to: nil, from: nil)

        #expect(vm.state == .idle)
        #expect(service.calls.isEmpty)
    }

    @Test("a new request cancels the one in flight")
    func cancelsInFlight() async {
        let service = StubRouteService()
        service.result = .success([sampleRoute()])
        let vm = RouteViewModel(service: service)

        vm.requestRoutes(to: destination("a"), from: MapCoordinate(latitude: 1, longitude: 1))
        let first = vm.currentTask
        vm.requestRoutes(to: destination("b"), from: MapCoordinate(latitude: 2, longitude: 2))

        #expect(first?.isCancelled == true)
        await vm.currentTask?.value
        guard case .loaded = vm.state else { Issue.record("expected .loaded"); return }
    }

    // MARK: - Manual refresh (M4.5)

    private func loaded(_ vm: RouteViewModel, service: StubRouteService) async {
        service.result = .success([sampleRoute()])
        vm.requestRoutes(to: destination(), from: MapCoordinate(latitude: 1, longitude: 1))
        await vm.currentTask?.value
    }

    @Test("refresh uses the current origin + remembered destination, keeps the loaded state")
    func refreshUsesCurrentOriginAndKeepsState() async {
        let service = StubRouteService()
        let vm = RouteViewModel(service: service)
        await loaded(vm, service: service)
        let loadedState = vm.state

        service.result = .success(routeSet(["route-0", "route-1"], durations: [.seconds(900), .seconds(800)]))
        vm.refreshRoutes(from: MapCoordinate(latitude: 9, longitude: 9))
        #expect(vm.refresh == .recalculating)
        #expect(vm.state == loadedState)          // preview / nav UI undisturbed
        await vm.refreshTask?.value

        guard case .options(let opts) = vm.refresh else { Issue.record("expected .options"); return }
        #expect(opts.routes.count == 2)
        #expect(vm.state == loadedState)          // still not auto-applied
        // second call used the fresh origin + the same destination
        #expect(service.calls.last?.origin == MapCoordinate(latitude: 9, longitude: 9))
        #expect(service.calls.last?.destination == destination().coordinate)
    }

    @Test("refresh with no current location reports it and makes no request")
    func refreshNoCurrentLocation() async {
        let service = StubRouteService()
        let vm = RouteViewModel(service: service)
        await loaded(vm, service: service)
        let callsBefore = service.calls.count

        vm.refreshRoutes(from: nil)

        #expect(vm.refresh == .noCurrentLocation)
        #expect(service.calls.count == callsBefore)
    }

    @Test("refresh with no remembered destination is a no-op")
    func refreshNeedsDestination() {
        let service = StubRouteService()
        let vm = RouteViewModel(service: service)
        vm.refreshRoutes(from: MapCoordinate(latitude: 1, longitude: 1))
        #expect(vm.refresh == .none)
        #expect(service.calls.isEmpty)
    }

    @Test("a failed refresh surfaces on `refresh`, not `state`")
    func refreshFailure() async {
        let service = StubRouteService()
        let vm = RouteViewModel(service: service)
        await loaded(vm, service: service)
        let loadedState = vm.state

        service.result = .failure(RouteError.unavailable)
        vm.refreshRoutes(from: MapCoordinate(latitude: 2, longitude: 2))
        await vm.refreshTask?.value

        #expect(vm.refresh == .failed(.unavailable))
        #expect(vm.state == loadedState)
    }

    @Test("clearRefresh dismisses a refresh result")
    func clearRefresh() async {
        let service = StubRouteService()
        let vm = RouteViewModel(service: service)
        await loaded(vm, service: service)

        service.result = .success([sampleRoute()])
        vm.refreshRoutes(from: MapCoordinate(latitude: 2, longitude: 2))
        await vm.refreshTask?.value
        #expect(vm.refresh != .none)

        vm.clearRefresh()
        #expect(vm.refresh == .none)
    }

    @Test("a fresh destination request clears any pending refresh")
    func requestClearsRefresh() async {
        let service = StubRouteService()
        let vm = RouteViewModel(service: service)
        await loaded(vm, service: service)
        service.result = .success([sampleRoute()])
        vm.refreshRoutes(from: MapCoordinate(latitude: 2, longitude: 2))
        await vm.refreshTask?.value

        vm.requestRoutes(to: destination("new"), from: MapCoordinate(latitude: 3, longitude: 3))
        #expect(vm.refresh == .none)
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

// MARK: - Multiple route options + selection in MapViewModel (M4.5)

@MainActor
@Suite("MapViewModel route options")
struct MapViewModelRouteOptionsTests {

    private func packet(_ lat: Double, _ lon: Double) -> LocationPacket {
        LocationPacket(latitude: lat, longitude: lon, speed: 0, heading: -1,
                       timestamp: Date(timeIntervalSince1970: 1_756_700_000))
    }

    /// A 3-point route from (0,0) to (0.1,0.1) bowing through `mid`.
    private func line(_ id: String, mid: MapCoordinate) -> Route {
        Route(id: id,
              polyline: [MapCoordinate(latitude: 0, longitude: 0),
                         mid,
                         MapCoordinate(latitude: 0.1, longitude: 0.1)],
              distanceMeters: 10_000, duration: .seconds(600),
              steps: [RouteStep(maneuver: .depart, instruction: "Go",
                                maneuverPoint: MapCoordinate(latitude: 0, longitude: 0),
                                polyline: [MapCoordinate(latitude: 0, longitude: 0),
                                           MapCoordinate(latitude: 0.1, longitude: 0.1)],
                                distanceMeters: 10_000)])
    }

    private func line(_ id: String, _ midLat: Double) -> Route {
        line(id, mid: MapCoordinate(latitude: midLat, longitude: 0.05))
    }

    private func previewing(_ vm: MapViewModel, options: RouteOptions) {
        vm.update(with: packet(0, 0))
        vm.setDestination(Destination(placeID: "d", name: "D", address: nil,
                                      coordinate: MapCoordinate(latitude: 0.1, longitude: 0.1)))
        vm.setRouteOptions(options)
    }

    @Test("in preview, the recommended route is active and every alternative is drawn secondary")
    func previewDrawsAllOptions() {
        let vm = MapViewModel()
        previewing(vm, options: RouteOptions([line("route-0", 0.02), line("route-1", 0.05), line("route-2", 0.08)])!)

        #expect(vm.route?.id == "route-0")
        let byRole = Dictionary(grouping: vm.content.polylines, by: \.role)
        #expect(byRole[.selected]?.map(\.id) == ["route-0"])
        #expect(Set(byRole[.alternative]?.map(\.id) ?? []) == ["route-1", "route-2"])
    }

    @Test("selecting an alternative in preview makes it active + re-fits the camera, no stale line")
    func selectAlternativeInPreview() {
        let vm = MapViewModel()
        // route-1 bows well outside the vehicle↔destination box, so fitting it
        // gives a visibly different camera.
        previewing(vm, options: RouteOptions([
            line("route-0", mid: MapCoordinate(latitude: 0.05, longitude: 0.05)),
            line("route-1", mid: MapCoordinate(latitude: -0.06, longitude: 0.05)),
        ])!)
        let firstCamera = vm.content.camera

        vm.selectRouteOption("route-1")

        #expect(vm.route?.id == "route-1")
        #expect(vm.routeOptions?.selected.id == "route-1")
        #expect(vm.canStartNavigation) // still previewing, still has a route + fix
        let byRole = Dictionary(grouping: vm.content.polylines, by: \.role)
        #expect(byRole[.selected]?.map(\.id) == ["route-1"])
        #expect(byRole[.alternative]?.map(\.id) == ["route-0"])
        #expect(vm.content.polylines.count == 2) // no third, stale line
        #expect(vm.content.camera != firstCamera) // re-fit to route-1
    }

    @Test("tapping a route polyline selects it in preview, and is ignored while navigating")
    func tappedRouteEvent() {
        let vm = MapViewModel()
        previewing(vm, options: RouteOptions([line("route-0", 0.02), line("route-1", 0.09)])!)

        vm.handle(.tappedRoute(id: "route-1"))
        #expect(vm.route?.id == "route-1")

        vm.startNavigation()
        vm.handle(.tappedRoute(id: "route-0"))
        #expect(vm.route?.id == "route-1") // unchanged while navigating
    }

    @Test("starting navigation uses the selected route and drops the preview alternatives")
    func startUsesSelectedRoute() {
        let vm = MapViewModel()
        previewing(vm, options: RouteOptions([line("route-0", 0.02), line("route-1", 0.09)])!)
        vm.selectRouteOption("route-1")

        vm.startNavigation()

        #expect(vm.mode == .navigating)
        #expect(vm.route?.id == "route-1")
        #expect(vm.routeOptions == nil)
        #expect(vm.content.polylines.map(\.id) == ["route-1"])
    }

    @Test("a single route needs no selector — one selected line, nil options")
    func singleRouteFallback() {
        let vm = MapViewModel()
        previewing(vm, options: RouteOptions([line("route-0", 0.05)])!)
        #expect(vm.routeOptions?.hasAlternatives == false)
        #expect(vm.content.polylines.map(\.role) == [.selected])
    }

    // MARK: refresh during navigation

    private func navigating(_ vm: MapViewModel) {
        previewing(vm, options: RouteOptions([line("route-0", 0.05)])!)
        vm.startNavigation()
    }

    @Test("offering refreshed options while navigating leaves the active route alone")
    func refreshOffersWithoutSwitching() {
        let vm = MapViewModel()
        navigating(vm)
        let refreshed = RouteOptions([line("alt-0", 0.03), line("alt-1", 0.06)])!

        vm.setRouteOptions(refreshed)

        #expect(vm.route?.id == "route-0")            // still driving the original
        #expect(vm.routeOptions?.routes.map(\.id) == ["alt-0", "alt-1"])
        // original active line (selected) + the two refreshed alternatives
        let byRole = Dictionary(grouping: vm.content.polylines, by: \.role)
        #expect(byRole[.selected]?.map(\.id) == ["route-0"])
        #expect(Set(byRole[.alternative]?.map(\.id) ?? []) == ["alt-0", "alt-1"])
    }

    @Test("adopting a refreshed route replaces the active route, resets progress, no stale geometry")
    func adoptRefreshedRoute() {
        let vm = MapViewModel()
        navigating(vm)
        vm.setNavigationProgress(NavigationProgress(stepIndex: 0, distanceToManeuverMeters: 100,
                                                    distanceRemainingMeters: 1_000, traveledMeters: 5_000,
                                                    isArrived: false))
        vm.setRouteOptions(RouteOptions([line("alt-0", 0.03), line("alt-1", 0.06)])!)

        vm.selectRouteOption("alt-1")

        #expect(vm.mode == .navigating)              // session not restarted
        #expect(vm.route?.id == "alt-1")
        #expect(vm.navigationProgress == nil)        // recalculated against the new route
        #expect(vm.content.vehicle.coordinate == MapCoordinate(latitude: 0, longitude: 0)) // indicator preserved
        // the old "route-0" geometry is gone
        #expect(vm.content.polylines.contains { $0.id == "route-0" } == false)
        let byRole = Dictionary(grouping: vm.content.polylines, by: \.role)
        #expect(byRole[.selected]?.map(\.id) == ["alt-1"])
        #expect(byRole[.alternative]?.map(\.id) == ["alt-0"])
    }

    @Test("adopting a refreshed route with follow off does not move the camera")
    func adoptRespectsFollowOff() {
        let vm = MapViewModel()
        navigating(vm)
        vm.handle(.cameraIdle(MapCameraPosition(center: MapCoordinate(latitude: 9, longitude: 9),
                                                zoom: 13, headingDegrees: 0), byUserGesture: true))
        #expect(vm.followsVehicle == false)
        let frozen = vm.content.camera

        vm.setRouteOptions(RouteOptions([line("alt-0", 0.03)])!)
        vm.selectRouteOption("alt-0")

        #expect(vm.route?.id == "alt-0")
        #expect(vm.content.camera == frozen) // untouched — follow is off
    }
}
