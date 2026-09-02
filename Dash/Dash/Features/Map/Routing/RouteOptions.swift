//
//  RouteOptions.swift
//  Dash
//
//  The SDK-neutral set of route choices the provider returned (M4.5) plus which
//  one is selected. `routes[0]` is the provider's recommended route; the rest
//  are alternatives. Selection lives here — `MapViewModel` holds a
//  `RouteOptions` and drives both map emphasis and which route Start / the info
//  panel use.
//
//  Pure value type: no SDK, no view logic. `summaries` produces one compact,
//  already-formatted row per route for the option selector.
//

import Foundation

nonisolated struct RouteOptions: Equatable, Sendable {

    /// Non-empty. `[0]` is the recommended route.
    let routes: [Route]

    /// The `id` of the currently selected route.
    private(set) var selectedID: String

    /// `nil` for an empty `routes` array (a programming / provider error — the
    /// service throws `.noRoute` instead of returning nothing).
    init?(_ routes: [Route], selectedID: String? = nil) {
        guard !routes.isEmpty else { return nil }
        self.routes = routes
        self.selectedID = selectedID.flatMap { id in
            routes.contains { $0.id == id } ? id : nil
        } ?? routes[0].id
    }

    var selected: Route {
        routes.first { $0.id == selectedID } ?? routes[0]
    }

    var recommended: Route { routes[0] }

    var hasAlternatives: Bool { routes.count > 1 }

    /// Every route except the selected one, in provider order.
    var alternatives: [Route] {
        routes.filter { $0.id != selectedID }
    }

    /// A copy with a different route selected. Unknown ids are ignored.
    func selecting(_ id: String) -> RouteOptions {
        guard routes.contains(where: { $0.id == id }) else { return self }
        var copy = self
        copy.selectedID = id
        return copy
    }

    // MARK: - Display

    /// One compact row per route for the selector control.
    var summaries: [RouteOptionSummary] {
        routes.enumerated().map { index, route in
            RouteOptionSummary(
                id: route.id,
                isSelected: route.id == selectedID,
                isRecommended: index == 0,
                distanceText: RouteFormat.distance(meters: route.distanceMeters),
                durationText: RouteFormat.duration(route.duration),
                label: Self.label(index: index, route: route, recommended: routes[0])
            )
        }
    }

    /// A short relative label: "Recommended" for the primary route, otherwise a
    /// comparison against it ("3 min faster" / "5 min longer" / "Similar time").
    private static func label(index: Int, route: Route, recommended: Route) -> String {
        guard index != 0 else { return "Recommended" }
        let deltaSeconds = route.duration.inSeconds - recommended.duration.inSeconds
        let minutes = Int((abs(deltaSeconds) / 60).rounded())
        if minutes < 1 { return "Similar time" }
        return deltaSeconds < 0 ? "\(minutes) min faster" : "\(minutes) min longer"
    }
}

/// One already-formatted row for the compact route-option selector.
nonisolated struct RouteOptionSummary: Equatable, Sendable, Identifiable {
    var id: String
    var isSelected: Bool
    var isRecommended: Bool
    var distanceText: String
    var durationText: String
    var label: String
}
