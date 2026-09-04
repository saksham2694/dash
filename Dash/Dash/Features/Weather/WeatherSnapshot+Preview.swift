//
//  WeatherSnapshot+Preview.swift
//  Dash — Weather feature
//
//  Sample `WeatherSnapshot` fixtures for `#Preview` blocks ONLY — wrapped in
//  `#if DEBUG` so none of this ships in a Release build. Production code never
//  falls back to fake weather data (M8.4 §2/§8); real snapshots only ever come
//  from `WeatherKitService`.
//

#if DEBUG
import Foundation

extension WeatherSnapshot {

    private static func hour(_ minutesFromNow: Int, _ celsius: Double, _ condition: WeatherCondition, symbol: String, daylight: Bool = true) -> WeatherHourEntry {
        WeatherHourEntry(
            date: Date().addingTimeInterval(TimeInterval(minutesFromNow * 60)),
            temperature: Measurement(value: celsius, unit: .celsius),
            condition: condition,
            symbolName: symbol,
            isDaylight: daylight
        )
    }

    private static func day(_ daysFromNow: Int, high: Double, low: Double, _ condition: WeatherCondition, symbol: String) -> WeatherDayEntry {
        WeatherDayEntry(
            date: Date().addingTimeInterval(TimeInterval(daysFromNow * 86_400)),
            highTemperature: Measurement(value: high, unit: .celsius),
            lowTemperature: Measurement(value: low, unit: .celsius),
            condition: condition,
            symbolName: symbol
        )
    }

    static let previewClearDay = WeatherSnapshot(
        localityName: "Bengaluru",
        // A non-round value on purpose — exercises the "always whole
        // numbers" formatting fix in previews, not just in tests.
        currentTemperature: Measurement(value: 29.4, unit: .celsius),
        condition: .clear,
        symbolName: "sun.max.fill",
        isDaylight: true,
        highTemperature: Measurement(value: 33, unit: .celsius),
        lowTemperature: Measurement(value: 21, unit: .celsius),
        hourly: [
            hour(-60, 27, .clear, symbol: "sun.max.fill"),
            hour(0, 29, .clear, symbol: "sun.max.fill"),
            hour(60, 30, .clear, symbol: "sun.max.fill"),
            hour(120, 31, .partlyCloudy, symbol: "cloud.sun.fill"),
            hour(180, 30, .partlyCloudy, symbol: "cloud.sun.fill"),
            hour(240, 27, .cloudy, symbol: "cloud.fill"),
            hour(300, 25, .cloudy, symbol: "cloud.fill"),
        ],
        dailyForecast: [
            day(1, high: 32, low: 22, .partlyCloudy, symbol: "cloud.sun.fill"),
            day(2, high: 31, low: 21, .cloudy, symbol: "cloud.fill"),
            day(3, high: 30, low: 20, .rain, symbol: "cloud.rain.fill"),
            day(4, high: 33, low: 22, .clear, symbol: "sun.max.fill"),
            day(5, high: 34, low: 23, .clear, symbol: "sun.max.fill"),
        ],
        fetchedAt: Date()
    )

    static let previewClearNight = WeatherSnapshot(
        localityName: "Bengaluru",
        currentTemperature: Measurement(value: 21, unit: .celsius),
        condition: .clear,
        symbolName: "moon.stars.fill",
        isDaylight: false,
        highTemperature: Measurement(value: 33, unit: .celsius),
        lowTemperature: Measurement(value: 19, unit: .celsius),
        hourly: [
            hour(-60, 22, .clear, symbol: "moon.stars.fill", daylight: false),
            hour(0, 21, .clear, symbol: "moon.stars.fill", daylight: false),
            hour(60, 20, .clear, symbol: "moon.stars.fill", daylight: false),
            hour(120, 20, .cloudy, symbol: "cloud.fill", daylight: false),
            hour(180, 19, .fog, symbol: "cloud.fog.fill", daylight: false),
            hour(240, 19, .fog, symbol: "cloud.fog.fill", daylight: false),
            hour(300, 22, .clear, symbol: "sun.max.fill"),
        ],
        dailyForecast: [
            day(1, high: 32, low: 20, .clear, symbol: "sun.max.fill"),
            day(2, high: 30, low: 19, .fog, symbol: "cloud.fog.fill"),
            day(3, high: 29, low: 18, .cloudy, symbol: "cloud.fill"),
            day(4, high: 31, low: 20, .clear, symbol: "sun.max.fill"),
        ],
        fetchedAt: Date()
    )

    static let previewRain = WeatherSnapshot(
        localityName: "Mumbai",
        currentTemperature: Measurement(value: 26, unit: .celsius),
        condition: .rain,
        symbolName: "cloud.rain.fill",
        isDaylight: true,
        highTemperature: Measurement(value: 27, unit: .celsius),
        lowTemperature: Measurement(value: 24, unit: .celsius),
        hourly: [
            hour(-60, 26, .rain, symbol: "cloud.rain.fill"),
            hour(0, 26, .rain, symbol: "cloud.rain.fill"),
            hour(60, 26, .rain, symbol: "cloud.rain.fill"),
            hour(120, 25, .thunderstorm, symbol: "cloud.bolt.rain.fill"),
            hour(180, 25, .rain, symbol: "cloud.rain.fill"),
            hour(240, 26, .cloudy, symbol: "cloud.fill"),
            hour(300, 26, .partlyCloudy, symbol: "cloud.sun.fill"),
        ],
        dailyForecast: [
            day(1, high: 28, low: 24, .thunderstorm, symbol: "cloud.bolt.rain.fill"),
            day(2, high: 27, low: 24, .rain, symbol: "cloud.rain.fill"),
            day(3, high: 29, low: 25, .cloudy, symbol: "cloud.fill"),
            day(4, high: 30, low: 25, .partlyCloudy, symbol: "cloud.sun.fill"),
            day(5, high: 30, low: 24, .rain, symbol: "cloud.rain.fill"),
        ],
        fetchedAt: Date()
    )

    static let previewSnow = WeatherSnapshot(
        localityName: "Manali",
        currentTemperature: Measurement(value: -2, unit: .celsius),
        condition: .snow,
        symbolName: "snowflake",
        isDaylight: true,
        highTemperature: Measurement(value: 1, unit: .celsius),
        lowTemperature: Measurement(value: -6, unit: .celsius),
        hourly: [
            hour(-60, -3, .snow, symbol: "snowflake"),
            hour(0, -2, .snow, symbol: "snowflake"),
            hour(60, -1, .snow, symbol: "snowflake"),
            hour(120, -1, .cloudy, symbol: "cloud.fill"),
            hour(180, -3, .cloudy, symbol: "cloud.fill"),
            hour(240, -5, .clear, symbol: "sun.max.fill"),
            hour(300, -6, .clear, symbol: "moon.stars.fill", daylight: false),
        ],
        dailyForecast: [
            day(1, high: 2, low: -5, .snow, symbol: "snowflake"),
            day(2, high: 0, low: -7, .snow, symbol: "snowflake"),
            day(3, high: 3, low: -4, .cloudy, symbol: "cloud.fill"),
            day(4, high: 4, low: -3, .clear, symbol: "sun.max.fill"),
        ],
        fetchedAt: Date()
    )
}
#endif
