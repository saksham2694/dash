//
//  WeatherKitService.swift
//  Dash — Weather feature
//
//  The production `WeatherService` — Apple WeatherKit (M8.4 §2, the preferred
//  provider). Fetches current + hourly + daily in one call, reverse-geocodes
//  the coordinate for a locality name (best-effort — `nil` on failure, never
//  blocks the weather fetch), and maps WeatherKit's own ~30-case
//  `WeatherCondition` down into this feature's small SDK-neutral vocabulary.
//
//  Requires the "WeatherKit" capability (Signing & Capabilities) and an App ID
//  with WeatherKit enabled in the Apple Developer portal — see
//  PROJECT_STATUS.md's M8.4 entry for the exact manual steps. Without that
//  entitlement every call throws; `WeatherViewModel` surfaces that as an
//  ordinary `.failed` presentation. This service NEVER falls back to
//  fake/mock data — a failure is a failure, shown honestly.
//
//  Uses the coordinate it's given — never its own `CLLocationManager`. The
//  caller (`WeatherViewModel`, via `WeatherLocationSource`) is Dash's existing
//  `LocationStore`.
//

import CoreLocation
import Foundation
import WeatherKit

struct WeatherKitService: WeatherService {

    private let service: WeatherKit.WeatherService
    private let geocoder: CLGeocoder

    init(service: WeatherKit.WeatherService = .shared, geocoder: CLGeocoder = CLGeocoder()) {
        self.service = service
        self.geocoder = geocoder
    }

    func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        async let weatherFetch = service.weather(for: location, including: .current, .hourly, .daily)
        async let localityFetch = Self.localityName(at: location, geocoder: geocoder)

        let (current, hourlyForecast, dailyForecast) = try await weatherFetch
        let locality = await localityFetch

        let hourly = hourlyForecast.prefix(6).map { hour in
            WeatherHourEntry(
                date: hour.date,
                temperature: hour.temperature,
                condition: WeatherCondition(weatherKit: hour.condition),
                symbolName: hour.symbolName,
                isDaylight: hour.isDaylight
            )
        }

        let today = dailyForecast.first

        // The upcoming-days strip (M8.4 "polish pass" §3): the next few days
        // AFTER today — today's already shown in the header's H:/L:. A short
        // glance strip, not a 7/10-day forecast.
        let upcomingDays = dailyForecast.dropFirst().prefix(5).map { day in
            WeatherDayEntry(
                date: day.date,
                highTemperature: day.highTemperature,
                lowTemperature: day.lowTemperature,
                condition: WeatherCondition(weatherKit: day.condition),
                symbolName: day.symbolName
            )
        }

        return WeatherSnapshot(
            localityName: locality,
            currentTemperature: current.temperature,
            condition: WeatherCondition(weatherKit: current.condition),
            symbolName: current.symbolName,
            isDaylight: current.isDaylight,
            highTemperature: today?.highTemperature ?? current.temperature,
            lowTemperature: today?.lowTemperature ?? current.temperature,
            hourly: Array(hourly),
            dailyForecast: Array(upcomingDays),
            fetchedAt: Date()
        )
    }

    /// Best-effort reverse geocode — `nil` on any failure (no network, rate
    /// limited, ocean coordinate, …). Never throws; a missing locality name
    /// must not fail the whole weather fetch.
    private static func localityName(at location: CLLocation, geocoder: CLGeocoder) async -> String? {
        (try? await geocoder.reverseGeocodeLocation(location))?.first?.locality
    }
}

extension WeatherCondition {

    /// Maps WeatherKit's own condition set into this feature's small,
    /// SDK-neutral vocabulary. `default:` is deliberate — WeatherKit's enum
    /// can grow new cases in a future OS; an unrecognised one degrades to
    /// `.other` rather than failing to compile or crashing.
    init(weatherKit condition: WeatherKit.WeatherCondition) {
        switch condition {
        case .clear, .mostlyClear, .hot:
            self = .clear
        case .partlyCloudy:
            self = .partlyCloudy
        case .cloudy, .mostlyCloudy, .blowingDust, .smoky:
            self = .cloudy
        case .foggy, .haze:
            self = .fog
        case .drizzle, .freezingDrizzle, .sunShowers, .rain, .heavyRain, .freezingRain, .hail:
            self = .rain
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms,
             .hurricane, .tropicalStorm:
            self = .thunderstorm
        case .flurries, .snow, .heavySnow, .blizzard, .blowingSnow, .sleet, .wintryMix,
             .sunFlurries, .frigid:
            self = .snow
        default:
            self = .other
        }
    }
}
