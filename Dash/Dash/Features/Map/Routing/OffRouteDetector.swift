//
//  OffRouteDetector.swift
//  Dash
//
//  Pure, SDK-neutral off-route detection for an active turn-by-turn session
//  (M4.6). Given the route geometry and a stream of vehicle fixes it classifies
//  each fix as on-route / possibly-off-route / confirmed-off-route and signals —
//  at most once per episode — when an automatic reroute is warranted.
//
//  Same spirit as `NavigationProgressCalculator`: no SDK, no `LocationStore`, no
//  Combine, no async. It reuses `RouteGeometry.project` (the M4.3 projection
//  utility) to measure how far the vehicle is from the drawn route.
//  `NavigationViewModel` owns an instance and feeds it every fix; the composing
//  view turns a confirmed signal into a `RouteViewModel.autoReroute(...)` call.
//
//  Deliberately conservative (named thresholds below). Tuned tighter after a
//  physical drive (M4.6 refinement, 2026-09-03) so a genuine wrong turn is
//  caught a road-width sooner — 20 m / 35 m / 3 fixes, was 40 / 70 / 4:
//    - a hysteresis band between "clearly on" (`onRouteToleranceMeters`) and
//      "clearly off" (`offRouteThresholdMeters`) stops a fix that straddles the
//      edge from flapping the status;
//    - a run of `confirmationFixCount` meaningful off-route fixes is required
//      before an episode is confirmed, so a single noisy fix — or two — never
//      triggers a reroute;
//    - once an episode has asked for a reroute it stays quiet for
//      `resignalAfterFixes` further fixes (covers a request the coordinator
//      dropped for cooldown / concurrency) and then, if still off-route, asks
//      again;
//    - rejoining the route (within `onRouteToleranceMeters`) ends the episode
//      and re-arms detection.
//

import Foundation

/// How the latest fix relates to the active route.
nonisolated enum OffRouteStatus: Equatable, Sendable {
    /// On, or close to, the route.
    case onRoute
    /// Drifted off, but not yet far enough / long enough to be sure — no reroute.
    case possiblyOffRoute
    /// Confirmed off the route — a reroute is warranted.
    case confirmedOffRoute
}

nonisolated struct OffRouteDetector: Equatable, Sendable {

    /// Within this distance of the route the vehicle counts as on-route and any
    /// episode in progress is cleared. (~1 lane width — inside normal GPS scatter
    /// while genuinely on the road.)
    static let onRouteToleranceMeters = 20.0

    /// Beyond this distance a fix counts as a "meaningful" off-route fix. The gap
    /// up from `onRouteToleranceMeters` is a hysteresis band — a fix there
    /// neither confirms nor clears. (~a road away from the route.)
    static let offRouteThresholdMeters = 35.0

    /// Consecutive meaningful off-route fixes needed to confirm an episode. Two
    /// is the floor that still can't be one noisy fix; three keeps a short burst
    /// of bad GPS from triggering while adding only ~1 s of latency at a 1 Hz
    /// fix rate.
    static let confirmationFixCount = 3

    /// After signalling, stay quiet for this many further fixes before signalling
    /// again for the same still-unresolved episode.
    static let resignalAfterFixes = 8

    private(set) var status: OffRouteStatus = .onRoute
    private var meaningfulOffRouteFixes = 0
    private var hasSignalledThisEpisode = false
    private var fixesSinceSignal = 0

    /// What the caller should do after feeding a fix.
    enum Outcome: Equatable, Sendable {
        case none
        /// The episode is confirmed and a fresh route should be requested now.
        case requestReroute
    }

    /// Re-arm detection — call when the navigated route changes (navigation
    /// starts, or a reroute is adopted) so the new route is judged from scratch.
    mutating func reset() {
        self = OffRouteDetector()
    }

    /// Feed the latest vehicle position and the route being navigated.
    mutating func record(position: MapCoordinate, on route: Route) -> Outcome {
        guard route.polyline.count >= 2,
              let projection = RouteGeometry.project(position, onto: route.polyline)
        else {
            return .none
        }
        let offset = projection.distanceFromInput

        // Firmly back on the route — the episode (if any) is over.
        if offset <= Self.onRouteToleranceMeters {
            reset()
            return .none
        }

        // Hysteresis band — hold what we had, don't count this fix.
        if offset < Self.offRouteThresholdMeters {
            if status == .onRoute { status = .possiblyOffRoute }
            if hasSignalledThisEpisode { fixesSinceSignal += 1 }
            return .none
        }

        // A meaningful off-route fix.
        meaningfulOffRouteFixes += 1
        if hasSignalledThisEpisode { fixesSinceSignal += 1 }

        guard meaningfulOffRouteFixes >= Self.confirmationFixCount else {
            status = .possiblyOffRoute
            return .none
        }

        status = .confirmedOffRoute

        if !hasSignalledThisEpisode {
            hasSignalledThisEpisode = true
            fixesSinceSignal = 0
            return .requestReroute
        }
        if fixesSinceSignal >= Self.resignalAfterFixes {
            fixesSinceSignal = 0
            return .requestReroute
        }
        return .none
    }
}
