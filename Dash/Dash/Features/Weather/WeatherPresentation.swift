//
//  WeatherPresentation.swift
//  Dash — Weather feature
//
//  What every Weather view renders — one value read from `WeatherViewModel`.
//  Pure — no SwiftUI. Separates "what happened while fetching" (loading /
//  failed / unavailable) from "what to show" (a `WeatherSnapshot`, with a
//  `stale` flag once it's aged past `WeatherRefreshPolicy.staleAfter` or a
//  background refresh failed) so the views never have to reach into the view
//  model's internal bookkeeping.
//

import Foundation

nonisolated enum WeatherPresentation: Equatable, Sendable {

    /// No GPS fix yet — nothing to fetch weather for.
    case unavailable

    /// The first fetch is in flight; no snapshot to show yet.
    case loading

    /// A fetch failed and there has never been a successful one to fall back
    /// to.
    case failed

    /// Real data. `stale` is set once it's aged past the refresh policy's
    /// `staleAfter`, or the most recent background refresh attempt failed —
    /// either way the views show it dimmed with a small "last updated" cue
    /// rather than pretending it's current.
    case loaded(WeatherSnapshot, stale: Bool)
}

extension WeatherPresentation {

    /// The background this presentation renders on — a calm neutral field
    /// while there's nothing real to show yet, the real
    /// `WeatherAppearanceResolver` mapping once there's a snapshot.
    var appearance: WeatherAppearance {
        switch self {
        case .unavailable, .loading, .failed:
            return .neutral
        case .loaded(let snapshot, _):
            return WeatherAppearanceResolver.appearance(for: snapshot.condition, isDaylight: snapshot.isDaylight)
        }
    }
}
