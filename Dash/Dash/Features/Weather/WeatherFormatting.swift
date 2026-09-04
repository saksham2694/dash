//
//  WeatherFormatting.swift
//  Dash — Weather feature
//
//  Pure, locale-aware text formatting for temperatures and hourly-forecast
//  times — one place instead of scattered `String(format:)`/`* 9/5 + 32` in
//  the views.
//
//  Temperature (M8.4 §6): "follow the system/local convention" — `usage:
//  .weather` reads the SAME per-category preference Apple's own Weather app
//  honours (a metric-system locale that has still chosen Fahrenheit for
//  weather in Settings gets Fahrenheit here too), so this needs no unit
//  preference of its own and adds no new Settings page.
//

import Foundation

nonisolated enum WeatherFormatting {

    /// `"72°F"` / `"25°C"` — ALWAYS a whole number (M8.4 "small fixes" pass —
    /// `.precision(.fractionLength(0))` forces zero decimal places; the
    /// earlier `.rounded()`-only version only set the rounding *rule*, not
    /// the displayed precision, so a non-round underlying value like 24.3°
    /// could still render with a decimal), in whichever unit the locale's
    /// weather convention uses.
    static func temperatureText(_ measurement: Measurement<UnitTemperature>, locale: Locale = .current) -> String {
        measurement.formatted(
            .measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
    }

    /// `"3 PM"` / `"15"` — locale-aware hour label for one hourly-forecast row.
    static func hourText(for date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, timeZone: timeZone).hour()
        )
    }

    /// `"Now"` for the first entry (within a minute of `now`), else the hour
    /// label — matches Apple Weather's own hourly-strip convention.
    static func hourText(for date: Date, relativeTo now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        abs(date.timeIntervalSince(now)) < 60 ? "Now" : hourText(for: date, locale: locale, timeZone: timeZone)
    }

    /// `"Wed"` — locale-aware short weekday label for one daily-forecast row.
    static func dayText(for date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated)
        )
    }
}
