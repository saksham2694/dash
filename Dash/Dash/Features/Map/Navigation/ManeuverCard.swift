//
//  ManeuverCard.swift
//  Dash
//
//  The presentational model for the top maneuver card (M4.3) plus the distance
//  formatting it uses. SDK-neutral and pure — `NavigationViewModel` builds a
//  `ManeuverCard` from the active `RouteStep` + `NavigationProgress`, and
//  `ManeuverCardView` just renders it.
//

import Foundation

/// Everything the maneuver card shows, already formatted.
nonisolated struct ManeuverCard: Equatable, Sendable {

    /// SF Symbol for the maneuver arrow.
    var iconSystemName: String

    /// Primary line — "Turn right", or the raw instruction when there is no
    /// natural phrase.
    var primaryText: String

    /// The road being joined / followed, when known ("MG Road").
    var detailText: String?

    /// Distance to the maneuver ("200 m", "1.4 km", "Now"). `nil` on arrival.
    var distanceText: String?

    /// This card is the end-of-route state rather than a maneuver.
    var isArrival: Bool

    /// The end-of-route card.
    static let arrived = ManeuverCard(
        iconSystemName: "flag.checkered",
        primaryText: "You have arrived",
        detailText: nil,
        distanceText: nil,
        isArrival: true
    )
}

/// Distance strings for turn-by-turn: metres rounded to a readable step below a
/// kilometre, one decimal of a kilometre above it.
nonisolated enum NavigationDistance {

    static func text(forMeters meters: Double) -> String {
        let m = max(0, meters)
        if m < 15 { return "Now" }
        if m < 1000 {
            let step: Double = m < 300 ? 10 : 50
            let rounded = (m / step).rounded() * step
            return "\(Int(rounded)) m"
        }
        let km = m / 1000
        return String(format: "%.1f km", km)
    }
}
