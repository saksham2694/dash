//
//  WeatherFeatureTests.swift
//  DashTests
//
//  M8.4 — the Weather mini-app's testable pure logic:
//    • `WeatherFeature` — stable id, supported sizes (compact/medium/full,
//      never large), real registration.
//    • `WeatherAppearanceResolver` — condition + day/night → appearance.
//    • `WeatherCondition(weatherKit:)` — the provider mapping.
//    • `WeatherRefreshPolicy` / `WeatherCoordinate.distance` — the
//      "don't hammer the API" caching logic.
//    • `WeatherViewModel` — fetch/state transitions against a fake service.
//    • `WeatherFormatting` — locale-aware temperature/hour text.
//
//  All fake weather data here is test-only — production code (`WeatherFeature`'s
//  default init) only ever constructs a real `WeatherKitService`.
//

import CoreLocation
import Foundation
import Testing
import WeatherKit
@testable import Dash

// MARK: - Fixtures

@MainActor
private final class FakeWeatherLocationSource: WeatherLocationSource {
    var currentCoordinate: WeatherCoordinate?
}

private struct FakeWeatherError: Error, Sendable, Equatable {}

/// A fixed-result service — success or failure, never changes.
private struct FakeWeatherService: Dash.WeatherService {
    let result: Result<WeatherSnapshot, FakeWeatherError>
    func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        try result.get()
    }
}

/// A service whose outcome can be flipped mid-test (an `actor` so mutation
/// stays safe across the `WeatherService: Sendable` boundary).
private actor ToggleableWeatherService: Dash.WeatherService {
    private var shouldFail = false
    private let result: WeatherSnapshot

    init(result: WeatherSnapshot) { self.result = result }

    func setShouldFail(_ value: Bool) { shouldFail = value }

    func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        if shouldFail { throw FakeWeatherError() }
        return result
    }
}

/// Counts how many times `fetchWeather` was actually called — proves the
/// refresh policy, not the caller, is what throttles repeat requests.
private actor FetchCountingService: Dash.WeatherService {
    private(set) var fetchCount = 0
    private let result: WeatherSnapshot

    init(result: WeatherSnapshot) { self.result = result }

    func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        fetchCount += 1
        return result
    }
}

// MARK: - WeatherFeature

@MainActor
@Suite("WeatherFeature")
struct WeatherFeatureTests {

    @Test("keeps the stable id the retired placeholder used")
    func stableID() {
        #expect(WeatherFeature.id == "weather")
        #expect(WeatherFeature().manifest.id == "weather")
        #expect(WeatherFeature().manifest.title == "Weather")
    }

    @Test("supports compact, medium, and full-screen — never large")
    func supportedSizes() {
        let manifest = WeatherFeature().manifest
        #expect(manifest.supportedSizes == [.compact, .medium, .full])
        #expect(!manifest.supportedSizes.contains(.large))
        #expect(manifest.supportedWidgetSizes == [.compact, .medium])
    }

    @Test("is registered in the default registry as a real feature")
    func registeredAsReal() {
        let registry = FeatureRegistry.makeDefault()
        #expect(registry.feature("weather") as? WeatherFeature != nil)
    }

    @Test("the dashboard Add-Widget picker offers exactly compact and medium")
    func widgetPickerSizes() {
        let manifest = WeatherFeature().manifest
        #expect(DashboardWidgetPickerView.offeredSizes(for: manifest) == [.compact, .medium])
    }

    @Test("the dashboard feature-reassignment picker never offers Weather at .large")
    func neverLargeReassignment() {
        let registry = FeatureRegistry.makeDefault()
        let eligible = DashboardFeaturePickerView.eligibleFeatures(registry.manifests, for: .large).map(\.id)
        #expect(!eligible.contains("weather"))
    }
}

// MARK: - WeatherAppearanceResolver

@Suite("WeatherAppearanceResolver")
struct WeatherAppearanceTests {

    @Test("clear day and clear night resolve to different, distinct palettes")
    func clearDayVsNight() {
        let day = WeatherAppearanceResolver.appearance(for: .clear, isDaylight: true)
        let night = WeatherAppearanceResolver.appearance(for: .clear, isDaylight: false)
        #expect(day != night)
    }

    @Test("snow and fog prefer dark content for contrast on a pale background")
    func paleBackgroundsPreferDarkContent() {
        #expect(WeatherAppearanceResolver.appearance(for: .snow, isDaylight: true).prefersDarkContent)
        #expect(WeatherAppearanceResolver.appearance(for: .fog, isDaylight: true).prefersDarkContent)
        #expect(WeatherAppearanceResolver.appearance(for: .other, isDaylight: true).prefersDarkContent)
    }

    @Test("bright conditions prefer light (white) content")
    func brightBackgroundsPreferLightContent() {
        #expect(!WeatherAppearanceResolver.appearance(for: .clear, isDaylight: true).prefersDarkContent)
        #expect(!WeatherAppearanceResolver.appearance(for: .rain, isDaylight: true).prefersDarkContent)
        #expect(!WeatherAppearanceResolver.appearance(for: .thunderstorm, isDaylight: true).prefersDarkContent)
    }

    @Test("night applies a scrim for conditions without their own night palette")
    func nightScrimApplied() {
        let cloudyDay = WeatherAppearanceResolver.appearance(for: .cloudy, isDaylight: true)
        let cloudyNight = WeatherAppearanceResolver.appearance(for: .cloudy, isDaylight: false)
        #expect(cloudyDay.nightScrimOpacity == 0)
        #expect(cloudyNight.nightScrimOpacity > 0)
    }

    @Test("resolution is pure — the same inputs always produce the same appearance")
    func deterministic() {
        for condition in Dash.WeatherCondition.allCases {
            for daylight in [true, false] {
                let a = WeatherAppearanceResolver.appearance(for: condition, isDaylight: daylight)
                let b = WeatherAppearanceResolver.appearance(for: condition, isDaylight: daylight)
                #expect(a == b)
            }
        }
    }
}

// MARK: - WeatherCondition(weatherKit:) — the provider mapping

@Suite("WeatherCondition(weatherKit:)")
struct WeatherConditionMappingTests {

    @Test("maps representative WeatherKit conditions into the right bucket")
    func representativeMapping() {
        #expect(WeatherCondition(weatherKit: .clear) == .clear)
        #expect(WeatherCondition(weatherKit: .mostlyClear) == .clear)
        #expect(WeatherCondition(weatherKit: .partlyCloudy) == .partlyCloudy)
        #expect(WeatherCondition(weatherKit: .cloudy) == .cloudy)
        #expect(WeatherCondition(weatherKit: .mostlyCloudy) == .cloudy)
        #expect(WeatherCondition(weatherKit: .foggy) == .fog)
        #expect(WeatherCondition(weatherKit: .haze) == .fog)
        #expect(WeatherCondition(weatherKit: .rain) == .rain)
        #expect(WeatherCondition(weatherKit: .heavyRain) == .rain)
        #expect(WeatherCondition(weatherKit: .drizzle) == .rain)
        #expect(WeatherCondition(weatherKit: .thunderstorms) == .thunderstorm)
        #expect(WeatherCondition(weatherKit: .isolatedThunderstorms) == .thunderstorm)
        #expect(WeatherCondition(weatherKit: .hurricane) == .thunderstorm)
        #expect(WeatherCondition(weatherKit: .snow) == .snow)
        #expect(WeatherCondition(weatherKit: .flurries) == .snow)
        #expect(WeatherCondition(weatherKit: .blizzard) == .snow)
    }

    @Test("an unmapped condition falls back to .other rather than crashing")
    func fallsBackToOther() {
        #expect(WeatherCondition(weatherKit: .windy) == .other)
        #expect(WeatherCondition(weatherKit: .breezy) == .other)
    }
}

// MARK: - WeatherCoordinate.distance

@Suite("WeatherCoordinate.distance")
struct WeatherCoordinateDistanceTests {

    @Test("distance to the same coordinate is zero")
    func zeroDistance() {
        let c = WeatherCoordinate(latitude: 12.9716, longitude: 77.5946)
        #expect(c.distance(to: c) == 0)
    }

    @Test("roughly matches a known great-circle distance")
    func knownDistance() {
        // Bengaluru → Chennai, actual great-circle distance ≈ 290 km.
        let bengaluru = WeatherCoordinate(latitude: 12.9716, longitude: 77.5946)
        let chennai = WeatherCoordinate(latitude: 13.0827, longitude: 80.2707)
        let distance = bengaluru.distance(to: chennai)
        #expect(distance > 280_000 && distance < 300_000)
    }
}

// MARK: - WeatherRefreshPolicy

@Suite("WeatherRefreshPolicy")
struct WeatherRefreshPolicyTests {

    private let policy = WeatherRefreshPolicy()
    private let origin = WeatherCoordinate(latitude: 12.9716, longitude: 77.5946)

    @Test("always refreshes when there's no prior fetch")
    func noPriorFetch() {
        #expect(policy.shouldRefresh(lastFetch: nil, currentCoordinate: origin, now: Date()))
    }

    @Test("does not refresh before the minimum interval, at the same location")
    func withinInterval() {
        let last = WeatherFetchRecord(coordinate: origin, date: Date())
        let now = last.date.addingTimeInterval(5 * 60)
        #expect(!policy.shouldRefresh(lastFetch: last, currentCoordinate: origin, now: now))
    }

    @Test("refreshes once the minimum interval has passed")
    func afterInterval() {
        let last = WeatherFetchRecord(coordinate: origin, date: Date())
        let now = last.date.addingTimeInterval(policy.minimumInterval + 1)
        #expect(policy.shouldRefresh(lastFetch: last, currentCoordinate: origin, now: now))
    }

    @Test("refreshes early once the car has moved far enough, after the movement floor")
    func earlyRefreshOnMovement() {
        let last = WeatherFetchRecord(coordinate: origin, date: Date())
        let farAway = WeatherCoordinate(latitude: origin.latitude + 1.0, longitude: origin.longitude)   // ≈111 km
        let now = last.date.addingTimeInterval(policy.minimumIntervalAfterMovement + 1)
        #expect(policy.shouldRefresh(lastFetch: last, currentCoordinate: farAway, now: now))
    }

    @Test("does not refresh on movement before the movement floor has passed, even if far")
    func movementFloorPreventsBurst() {
        let last = WeatherFetchRecord(coordinate: origin, date: Date())
        let farAway = WeatherCoordinate(latitude: origin.latitude + 1.0, longitude: origin.longitude)
        let now = last.date.addingTimeInterval(policy.minimumIntervalAfterMovement - 1)
        #expect(!policy.shouldRefresh(lastFetch: last, currentCoordinate: farAway, now: now))
    }

    @Test("small movement under the threshold does not trigger an early refresh")
    func smallMovementDoesNotRefresh() {
        let last = WeatherFetchRecord(coordinate: origin, date: Date())
        let nearby = WeatherCoordinate(latitude: origin.latitude + 0.001, longitude: origin.longitude)   // ≈111 m
        let now = last.date.addingTimeInterval(policy.minimumIntervalAfterMovement + 1)
        #expect(!policy.shouldRefresh(lastFetch: last, currentCoordinate: nearby, now: now))
    }

    @Test("a clock that appears to move backwards does not trigger a refresh")
    func clockBackwardsIsSafe() {
        let last = WeatherFetchRecord(coordinate: origin, date: Date())
        let now = last.date.addingTimeInterval(-10)
        #expect(!policy.shouldRefresh(lastFetch: last, currentCoordinate: origin, now: now))
    }
}

// MARK: - WeatherViewModel

@MainActor
@Suite("WeatherViewModel")
struct WeatherViewModelTests {

    @Test("stays unavailable with no location fix yet")
    func noLocation() {
        let vm = WeatherViewModel(service: FakeWeatherService(result: .success(.previewClearDay)))
        #expect(vm.presentation() == .unavailable)
    }

    @Test("a successful fetch transitions to .loaded, not stale")
    func successfulFetch() async {
        let source = FakeWeatherLocationSource()
        source.currentCoordinate = WeatherCoordinate(latitude: 1, longitude: 2)
        let vm = WeatherViewModel(service: FakeWeatherService(result: .success(.previewClearDay)))
        vm.connect(to: source)

        await vm.locationDidChange()

        guard case .loaded(let snapshot, let stale) = vm.presentation() else {
            Issue.record("expected .loaded, got \(vm.presentation())")
            return
        }
        #expect(snapshot == .previewClearDay)
        #expect(stale == false)
    }

    @Test("a failed fetch with no prior data reports .failed")
    func failedFetchNoData() async {
        let source = FakeWeatherLocationSource()
        source.currentCoordinate = WeatherCoordinate(latitude: 1, longitude: 2)
        let vm = WeatherViewModel(service: FakeWeatherService(result: .failure(FakeWeatherError())))
        vm.connect(to: source)

        await vm.locationDidChange()

        #expect(vm.presentation() == .failed)
    }

    @Test("a failed refresh after a success keeps showing the last snapshot, marked stale")
    func failedRefreshKeepsStaleData() async {
        let source = FakeWeatherLocationSource()
        source.currentCoordinate = WeatherCoordinate(latitude: 1, longitude: 2)
        var policy = WeatherRefreshPolicy()
        policy.minimumInterval = 1
        policy.minimumIntervalAfterMovement = 0

        let service = ToggleableWeatherService(result: .previewClearDay)
        let vm = WeatherViewModel(service: service, policy: policy)
        vm.connect(to: source)

        let t0 = Date()
        await vm.locationDidChange(at: t0)
        guard case .loaded = vm.presentation(at: t0) else {
            Issue.record("expected the first fetch to succeed")
            return
        }

        await service.setShouldFail(true)
        let t1 = t0.addingTimeInterval(2)
        await vm.locationDidChange(at: t1)

        guard case .loaded(_, let stale) = vm.presentation(at: t1) else {
            Issue.record("expected .loaded(stale: true), got \(vm.presentation(at: t1))")
            return
        }
        #expect(stale)
    }

    @Test("data aged past staleAfter is presented as stale even without a failed refresh")
    func agingMarksStale() async {
        let source = FakeWeatherLocationSource()
        source.currentCoordinate = WeatherCoordinate(latitude: 1, longitude: 2)
        let vm = WeatherViewModel(
            service: FakeWeatherService(result: .success(.previewClearDay)),
            policy: WeatherRefreshPolicy(staleAfter: 60)
        )
        vm.connect(to: source)

        let t0 = Date()
        await vm.locationDidChange(at: t0)

        guard case .loaded(_, let freshStale) = vm.presentation(at: t0.addingTimeInterval(10)) else {
            Issue.record("expected .loaded"); return
        }
        #expect(freshStale == false)

        guard case .loaded(_, let agedStale) = vm.presentation(at: t0.addingTimeInterval(120)) else {
            Issue.record("expected .loaded"); return
        }
        #expect(agedStale == true)
    }

    @Test("the refresh policy — not the caller — throttles repeat calls at the same location")
    func policyThrottlesRepeatCalls() async {
        let source = FakeWeatherLocationSource()
        source.currentCoordinate = WeatherCoordinate(latitude: 1, longitude: 2)
        let counter = FetchCountingService(result: .previewClearDay)
        let vm = WeatherViewModel(service: counter)
        vm.connect(to: source)

        let t0 = Date()
        await vm.locationDidChange(at: t0)
        await vm.locationDidChange(at: t0.addingTimeInterval(1))
        await vm.locationDidChange(at: t0.addingTimeInterval(2))

        #expect(await counter.fetchCount == 1)
    }

    @Test("no fetch happens without a connected location source")
    func noFetchWithoutSource() async {
        let counter = FetchCountingService(result: .previewClearDay)
        let vm = WeatherViewModel(service: counter)
        await vm.locationDidChange()
        #expect(await counter.fetchCount == 0)
        #expect(vm.presentation() == .unavailable)
    }
}

// MARK: - WeatherFormatting

@Suite("WeatherFormatting")
struct WeatherFormattingTests {

    @Test("temperature follows the local weather convention")
    func temperatureFollowsLocale() {
        let celsius25 = Measurement(value: 25, unit: UnitTemperature.celsius)
        let usText = WeatherFormatting.temperatureText(celsius25, locale: Locale(identifier: "en_US"))
        let inText = WeatherFormatting.temperatureText(celsius25, locale: Locale(identifier: "en_IN"))

        #expect(usText.contains("77"))     // 25°C == 77°F, the US weather convention
        #expect(inText.contains("25"))     // stays Celsius in India
    }

    @Test("temperature is always a whole number, even for a non-round underlying value")
    func temperatureIsAlwaysWhole() {
        let locale = Locale(identifier: "en_IN")
        let values: [Double] = [24.3, -2.7, 0.5, 18.999, 100.0001]
        for celsius in values {
            let text = WeatherFormatting.temperatureText(Measurement(value: celsius, unit: .celsius), locale: locale)
            #expect(!text.contains("."), "\(celsius)°C formatted with a decimal point: \(text)")
            // en_IN's decimal separator is also "." — a locale-specific
            // separator wouldn't be caught by the check above, so also
            // confirm there are no digits after any separator character.
            #expect(text.range(of: #"[.,]\d"#, options: .regularExpression) == nil, "\(celsius)°C: \(text)")
        }
    }

    @Test("hour text renders the correct hour for the given time zone")
    func hourTextUsesTimeZone() {
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 1
        components.hour = 15; components.minute = 0
        var calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        calendar.timeZone = utc
        let date = calendar.date(from: components)!

        let text = WeatherFormatting.hourText(for: date, locale: Locale(identifier: "en_US"), timeZone: utc)
        #expect(text.contains("3"))   // 15:00 UTC → "3 PM" in en_US
    }

    @Test("day text renders the correct abbreviated weekday for the given time zone")
    func dayTextUsesTimeZone() {
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 7   // a Wednesday
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(identifier: "UTC")!
        calendar.timeZone = utc
        let date = calendar.date(from: components)!

        let text = WeatherFormatting.dayText(for: date, locale: Locale(identifier: "en_US"), timeZone: utc)
        #expect(text == "Wed")
    }

    @Test("\"Now\" is used only within a minute of the reference date")
    func nowLabel() {
        let now = Date()
        #expect(WeatherFormatting.hourText(for: now, relativeTo: now) == "Now")
        #expect(WeatherFormatting.hourText(for: now.addingTimeInterval(30), relativeTo: now) == "Now")
        #expect(WeatherFormatting.hourText(for: now.addingTimeInterval(3600), relativeTo: now) != "Now")
    }
}
