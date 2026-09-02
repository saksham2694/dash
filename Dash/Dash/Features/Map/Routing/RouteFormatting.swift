//
//  RouteFormatting.swift
//  Dash
//
//  Pure, SDK-neutral formatting for route summary / ETA figures (M4.4). Kept out
//  of the SwiftUI views so it is unit-testable; the maneuver-countdown distance
//  string stays separate in `NavigationDistance` (it has a "Now" band that makes
//  no sense for a route total).
//
//  Clock formatting goes through `Date.FormatStyle` with an injectable
//  locale / time zone — the panel uses the viewer's own settings; tests pin them.
//

import Foundation

nonisolated enum RouteFormat {

    /// A whole-route or remaining distance: "40 m" / "1.4 km" / "23 km".
    static func distance(meters: Double) -> String {
        let m = max(0, meters)
        if m < 950 {
            let step: Double = m < 100 ? 10 : 50
            return "\(Int((m / step).rounded() * step)) m"
        }
        let km = m / 1000
        if km < 10 { return String(format: "%.1f km", km) }
        return "\(Int(km.rounded())) km"
    }

    /// A travel time: "< 1 min" / "8 min" / "1 hr" / "1 hr 15 min".
    static func duration(_ duration: Duration) -> String {
        let seconds = max(0, duration.inSeconds)
        if seconds < 30 { return "< 1 min" }

        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        if totalMinutes < 60 { return "\(totalMinutes) min" }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }

    /// A clock time in the viewer's locale / time zone ("3:45 PM", "15:45").
    static func time(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

extension Duration {

    /// This duration's length in seconds as a `Double`.
    nonisolated var inSeconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}
