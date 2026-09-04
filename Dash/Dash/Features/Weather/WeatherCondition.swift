//
//  WeatherCondition.swift
//  Dash — Weather feature
//
//  A small, SDK-neutral condition vocabulary the rest of the feature (state,
//  appearance, views, tests) is built on. WeatherKit's own `WeatherCondition`
//  has ~30 cases; a future alternate provider would have its own. Nobody
//  outside `WeatherKitService.swift` (the one file that maps into this) knows
//  WeatherKit's case list — the same decoupling `MapContent` gives the Map
//  feature from a specific map SDK.
//

import Foundation

nonisolated enum WeatherCondition: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    case clear
    case partlyCloudy
    case cloudy
    case rain
    case thunderstorm
    case snow
    case fog
    /// Anything not confidently bucketed above (windy, blowing dust, an
    /// unrecognised future provider case, …) — a safe, readable fallback
    /// rather than a crash or a `nil`.
    case other
}
