//
//  WeatherSnapshot.swift
//  Dash — Weather feature
//
//  One fetched weather result — everything the compact/medium/full-screen
//  views need, and nothing they don't (M8.4 §2: current temp/condition/icon,
//  today's high/low, ~6 upcoming hours, enough condition/day-night info to
//  drive presentation colour). SDK-neutral value types; `WeatherKitService` is
//  the only file that builds one from a real provider response.
//

import Foundation

nonisolated struct WeatherSnapshot: Equatable, Sendable {

    /// Reverse-geocoded place name for the fetched coordinate, if resolvable.
    /// "if available" (M8.4 §3) — views fall back to a generic label when nil.
    var localityName: String?

    var currentTemperature: Measurement<UnitTemperature>
    var condition: WeatherCondition
    /// The provider's own SF Symbol name for the current condition — native
    /// SF Symbols, not proprietary artwork (M8.4 §5).
    var symbolName: String
    var isDaylight: Bool

    var highTemperature: Measurement<UnitTemperature>
    var lowTemperature: Measurement<UnitTemperature>

    /// Roughly the next 6 hours (M8.4 §2/§4), nearest first.
    var hourly: [WeatherHourEntry]

    /// A short upcoming multi-day forecast (M8.4 "polish pass" §3) — a
    /// handful of days, NOT today (today's already the header's high/low).
    /// Deliberately small: this is a glance strip, not a 7/10-day forecast.
    var dailyForecast: [WeatherDayEntry]

    /// When this snapshot was fetched — `WeatherViewModel.presentation(at:)`
    /// ages it against `WeatherRefreshPolicy.staleAfter`.
    var fetchedAt: Date
}

nonisolated struct WeatherHourEntry: Identifiable, Equatable, Sendable {

    var date: Date
    var temperature: Measurement<UnitTemperature>
    var condition: WeatherCondition
    var symbolName: String
    var isDaylight: Bool

    var id: Date { date }
}

nonisolated struct WeatherDayEntry: Identifiable, Equatable, Sendable {

    var date: Date
    var highTemperature: Measurement<UnitTemperature>
    var lowTemperature: Measurement<UnitTemperature>
    var condition: WeatherCondition
    var symbolName: String

    var id: Date { date }
}
