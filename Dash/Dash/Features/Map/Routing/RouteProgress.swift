//
//  RouteProgress.swift
//  Dash
//
//  The provider-neutral navigation progress engine (M4.3): given the active
//  `Route` and the vehicle's current coordinate, work out which maneuver is
//  upcoming, how far away it is, and how much of the route remains.
//
//  Pure value logic — no SDK, no `LocationStore`, no Combine. `NavigationViewModel`
//  drives it from the location pipeline; `MapViewModel` reads the result for the
//  navigation camera. It never talks to `GoogleMapProvider`.
//
//  Model: progress is a single scalar `traveledMeters` measured along the
//  concatenated `Route.steps` geometry. `steps[i]` is the maneuver performed at
//  `steps[i].maneuverPoint` (cumulative distance `startDistances[i]`), then
//  `steps[i].distanceMeters` of travel to the next maneuver. The *upcoming*
//  maneuver is the first step whose maneuver point is still ahead of
//  `traveledMeters`; `stepIndex` points at it and the maneuver card shows it.
//
//  GPS-noise handling (see `next(_:route:position:)`):
//    - progress only moves forward (`max` with the previous value);
//    - a single fix advances the displayed maneuver by at most one, so a stray
//      jump never skips a turn (`oneManeuverCap`);
//    - a fix that lands more than `offRouteIgnoreMeters` from every step is
//      treated as noise and ignored (off-route detection proper is out of scope
//      for M4.3).
//

import Foundation

/// A snapshot of how far through the route the driver is.
nonisolated struct NavigationProgress: Equatable, Sendable {

    /// Index into `Route.steps` of the maneuver the driver is approaching (or,
    /// once every maneuver point is behind them, the final step). The maneuver
    /// card shows `steps[stepIndex]`.
    var stepIndex: Int

    /// Distance from the current position to the upcoming maneuver point (or, on
    /// the final step, to the destination), along the route, in metres.
    var distanceToManeuverMeters: Double

    /// Distance from the current position to the destination, along the route,
    /// in metres.
    var distanceRemainingMeters: Double

    /// Distance travelled from the route origin along the step geometry, metres.
    /// Carried between snapshots so progress stays monotonic under GPS noise.
    var traveledMeters: Double

    /// The driver has reached the destination.
    var isArrived: Bool
}

nonisolated enum NavigationProgressCalculator {

    /// Within this many metres of the destination counts as arrived.
    static let arrivalRadiusMeters = 25.0

    /// A fix further than this from every step is treated as noise and does not
    /// move progress (off-route detection proper is out of scope for M4.3).
    static let offRouteIgnoreMeters = 80.0

    // MARK: - Entry points

    /// First progress snapshot when navigation starts.
    static func initial(for route: Route, at position: MapCoordinate) -> NavigationProgress {
        let metrics = RouteMetrics(route)
        guard metrics.isUsable else {
            return NavigationProgress(
                stepIndex: 0,
                distanceToManeuverMeters: 0,
                distanceRemainingMeters: route.distanceMeters,
                traveledMeters: 0,
                isArrived: false
            )
        }
        let traveled = metrics.travel(at: position) ?? 0
        return metrics.progress(traveled: traveled)
    }

    /// Next progress snapshot from a new fix, given the previous one.
    static func next(_ previous: NavigationProgress,
                     route: Route,
                     position: MapCoordinate) -> NavigationProgress {
        let metrics = RouteMetrics(route)
        guard metrics.isUsable else { return previous }

        // A fix far from every step is noise — keep the previous maneuver.
        guard let raw = metrics.travel(at: position, maxOffset: offRouteIgnoreMeters) else {
            return previous
        }

        var traveled = max(previous.traveledMeters, raw)                              // forward only
        traveled = min(traveled, metrics.oneManeuverCap(from: previous.traveledMeters)) // one maneuver max

        return metrics.progress(traveled: traveled)
    }
}

// MARK: - Remaining travel time (M4.4)

extension NavigationProgress {

    /// Estimated remaining travel time. M4.4 has no traffic model — this scales
    /// the route's total `duration` by the fraction of distance still to go, so
    /// it stays consistent with `distanceRemainingMeters` and never re-derives
    /// the route. `.zero` on arrival or for a zero-length route.
    nonisolated func remainingDuration(along route: Route) -> Duration {
        guard route.distanceMeters > 0, !isArrived else { return .zero }
        let fraction = min(1, max(0, distanceRemainingMeters / route.distanceMeters))
        return .seconds(route.duration.inSeconds * fraction)
    }
}

// MARK: - Route measurement

/// Cumulative geometry of a route's steps. All distances in metres.
private nonisolated struct RouteMetrics {

    let steps: [RouteStep]
    /// `startDistances[i]` — distance from the origin to `steps[i].maneuverPoint`.
    let startDistances: [Double]
    let total: Double

    init(_ route: Route) {
        steps = route.steps
        var starts: [Double] = []
        var acc = 0.0
        for step in steps {
            starts.append(acc)
            let length = step.distanceMeters > 0 ? step.distanceMeters : RouteGeometry.length(step.polyline)
            acc += length
        }
        startDistances = starts
        total = acc
    }

    var isUsable: Bool { steps.count >= 2 && total > 0 }

    /// Distance travelled along the step sequence for `position` — the nearest
    /// projection across all steps. `nil` when the nearest step is further than
    /// `maxOffset`.
    func travel(at position: MapCoordinate, maxOffset: Double = .greatestFiniteMagnitude) -> Double? {
        var bestOffset = Double.greatestFiniteMagnitude
        var bestTravel = 0.0
        for (i, step) in steps.enumerated() {
            guard let projection = RouteGeometry.project(position, onto: step.polyline) else { continue }
            if projection.distanceFromInput < bestOffset {
                bestOffset = projection.distanceFromInput
                bestTravel = startDistances[i] + projection.distanceAlong
            }
        }
        guard bestOffset <= maxOffset else { return nil }
        return min(bestTravel, total)
    }

    /// The index of the maneuver the driver is approaching at `traveled` — the
    /// first step whose maneuver point is still ahead. Falls back to the last
    /// step once every maneuver point is behind.
    func upcomingIndex(forTraveled traveled: Double) -> Int {
        for i in steps.indices where startDistances[i] > traveled + 0.5 {
            return i
        }
        return steps.count - 1
    }

    /// The furthest `traveled` value allowed for a fix so it advances past at
    /// most one maneuver relative to `from`.
    func oneManeuverCap(from traveled: Double) -> Double {
        let allowed = upcomingIndex(forTraveled: traveled) + 1
        guard allowed < steps.count else { return total }
        // Stop just short of the maneuver *after* the current upcoming one.
        return max(traveled, startDistances[allowed] - 1)
    }

    func progress(traveled: Double) -> NavigationProgress {
        let clamped = max(0, min(traveled, total))
        let upcoming = upcomingIndex(forTraveled: clamped)
        let onFinalStep = startDistances[upcoming] <= clamped // no maneuver point ahead

        let distanceRemaining = max(0, total - clamped)
        let distanceToManeuver = onFinalStep
            ? distanceRemaining
            : max(0, startDistances[upcoming] - clamped)
        let isArrived = onFinalStep && distanceRemaining <= NavigationProgressCalculator.arrivalRadiusMeters

        return NavigationProgress(
            stepIndex: upcoming,
            distanceToManeuverMeters: distanceToManeuver,
            distanceRemainingMeters: distanceRemaining,
            traveledMeters: clamped,
            isArrived: isArrived
        )
    }
}
