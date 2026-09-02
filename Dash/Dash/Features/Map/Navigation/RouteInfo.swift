//
//  RouteInfo.swift
//  Dash
//
//  The SDK-neutral display model for the route-info panel (M4.4): distance,
//  travel time and ETA, already formatted. Two flavours —
//
//    - `.preview`   — whole-route figures shown under the route preview, ETA =
//                     now + the route's full duration.
//    - `.remaining` — live figures during navigation, driven off the existing
//                     `NavigationProgress` + `Route` (no duplicate route maths),
//                     ETA = now + the remaining duration.
//
//  Pure: `RouteInfoPanelView` just renders one of these. Reuses `Route.duration`
//  / `Route.distanceMeters` and `NavigationProgress` — it never re-derives the
//  route.
//

import Foundation

nonisolated struct RouteInfo: Equatable, Sendable {

    /// Which set of figures this is — drives the panel's labels + accent so the
    /// preview panel reads distinctly from the live one.
    enum Kind: Equatable, Sendable {
        case preview
        case remaining

        /// Column headers for the panel. Deliberately different per kind.
        var labels: (distance: String, duration: String, eta: String) {
            switch self {
            case .preview:   return ("Distance", "Time", "Arrival")
            case .remaining: return ("Remaining", "Time left", "ETA")
            }
        }
    }

    var kind: Kind
    var distanceText: String
    var durationText: String
    var etaText: String
    /// The absolute arrival time, unformatted.
    var etaDate: Date

    // MARK: - Builders

    /// Route preview — whole-route distance + duration, ETA = `now` + duration.
    static func preview(
        route: Route,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> RouteInfo {
        make(
            kind: .preview,
            distanceMeters: route.distanceMeters,
            remaining: route.duration,
            now: now, locale: locale, timeZone: timeZone
        )
    }

    /// Live navigation — remaining distance from `progress`, remaining duration
    /// scaled from the route, ETA = `now` + that remaining duration.
    static func remaining(
        route: Route,
        progress: NavigationProgress,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> RouteInfo {
        make(
            kind: .remaining,
            distanceMeters: progress.distanceRemainingMeters,
            remaining: progress.remainingDuration(along: route),
            now: now, locale: locale, timeZone: timeZone
        )
    }

    private static func make(
        kind: Kind,
        distanceMeters: Double,
        remaining: Duration,
        now: Date,
        locale: Locale,
        timeZone: TimeZone
    ) -> RouteInfo {
        let eta = now.addingTimeInterval(max(0, remaining.inSeconds))
        return RouteInfo(
            kind: kind,
            distanceText: RouteFormat.distance(meters: distanceMeters),
            durationText: RouteFormat.duration(remaining),
            etaText: RouteFormat.time(eta, locale: locale, timeZone: timeZone),
            etaDate: eta
        )
    }
}
