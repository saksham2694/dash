//
//  NavigationViewModel.swift
//  Dash
//
//  Orchestrates an active turn-by-turn session (M4.3): holds the route being
//  navigated, advances `NavigationProgress` as fixes arrive, and exposes the
//  maneuver card + progress for the map camera.
//
//  Mirrors the M3 `RouteViewModel` pattern — SDK-free, holds no `LocationStore`,
//  no GPS logic of its own. The composing view feeds it the latest coordinate
//  (already pulled from `LocationStore`) and relays `progress` to `MapViewModel`,
//  exactly as it relays a loaded `Route` via `setRoute(_:)`.
//
//  Scope (M4.3): guidance display + progress only. No rerouting, no off-route
//  detection, no alternative routes, no voice — see the milestone notes.
//
//  M4.4 adds `routeInfo(now:)` — the remaining distance / time / ETA figures for
//  the live info panel, derived from the existing `Route` + `NavigationProgress`.
//

import Combine
import Foundation

@MainActor
final class NavigationViewModel: ObservableObject {

    enum State: Equatable {
        /// Not navigating.
        case inactive
        /// Navigating — the driver is en route to the next maneuver.
        case navigating(NavigationProgress)
        /// The driver has reached the destination.
        case arrived
    }

    @Published private(set) var state: State = .inactive

    private(set) var route: Route?

    var isActive: Bool {
        if case .inactive = state { return false }
        return true
    }

    /// The current progress snapshot, or `nil` when not actively navigating.
    var progress: NavigationProgress? {
        if case .navigating(let progress) = state { return progress }
        return nil
    }

    /// The maneuver the driver is approaching, or `nil` when not navigating.
    var currentStep: RouteStep? {
        guard let route, let progress, route.steps.indices.contains(progress.stepIndex) else { return nil }
        return route.steps[progress.stepIndex]
    }

    // MARK: - Session lifecycle

    /// Begin navigating `route` from `origin`. A route with no steps or a missing
    /// origin leaves the session inactive (the Start action is gated on both, so
    /// this is just belt-and-braces).
    func start(route: Route, from origin: MapCoordinate?) {
        guard !route.steps.isEmpty, let origin else {
            self.route = nil
            state = .inactive
            return
        }
        self.route = route
        let progress = NavigationProgressCalculator.initial(for: route, at: origin)
        state = progress.isArrived ? .arrived : .navigating(progress)
    }

    /// End the session and return to inactive.
    func stop() {
        route = nil
        state = .inactive
    }

    /// Feed in the latest vehicle coordinate. No-op unless actively navigating.
    func update(with coordinate: MapCoordinate?) {
        guard let route, let coordinate, case .navigating(let previous) = state else { return }
        let progress = NavigationProgressCalculator.next(previous, route: route, position: coordinate)
        state = progress.isArrived ? .arrived : .navigating(progress)
    }

    // MARK: - Display

    /// The maneuver card to show, or `nil` when there is nothing to display.
    var maneuverCard: ManeuverCard? {
        switch state {
        case .inactive:
            return nil
        case .arrived:
            return .arrived
        case .navigating(let progress):
            guard let step = currentStep else { return nil }
            return ManeuverCard(
                iconSystemName: step.maneuver.symbolName,
                primaryText: step.primaryText,
                detailText: step.roadName,
                distanceText: NavigationDistance.text(forMeters: progress.distanceToManeuverMeters),
                isArrival: step.maneuver == .arrive
            )
        }
    }

    /// Remaining distance / time / ETA for the live info panel (M4.4), or `nil`
    /// when there is nothing to show (not navigating, or arrived — the maneuver
    /// card covers arrival). ETA is computed from `now` so callers pass a fresh
    /// clock each render.
    func routeInfo(now: Date = Date()) -> RouteInfo? {
        guard let route, case .navigating(let progress) = state else { return nil }
        return .remaining(route: route, progress: progress, now: now)
    }
}
