//
//  WeatherRefreshPolicy.swift
//  Dash — Weather feature
//
//  Pure "should we actually hit the network right now" logic (M8.4 §2/§8:
//  "do not hammer the API... sensible caching/refresh behaviour"). Kept
//  separate from `WeatherViewModel` so it's trivially unit-tested without
//  async/mock plumbing.
//
//  `WeatherViewModel.locationDidChange(...)` is cheap to call on every GPS
//  packet (~1 Hz) — this policy is what keeps the actual WeatherKit fetch rare:
//  normally once every `minimumInterval`, or sooner only once the car has
//  moved `minimumMovementMeters` AND at least `minimumIntervalAfterMovement`
//  has passed since the last fetch (so a GPS jitter near the threshold can't
//  trigger a burst of requests).
//

import Foundation

nonisolated struct WeatherRefreshPolicy: Equatable, Sendable {

    /// Always re-fetch once this long has passed since the last successful
    /// fetch, regardless of movement. Weather doesn't change fast enough to
    /// need continuous polling.
    var minimumInterval: TimeInterval = 15 * 60

    /// Re-fetch sooner than `minimumInterval` if the car has moved at least
    /// this far from where the last fetch was made (a new city's weather
    /// could be quite different).
    var minimumMovementMeters: Double = 5_000

    /// The movement short-circuit above only applies once this much time has
    /// passed since the last fetch — a floor so a single noisy GPS jump can't
    /// immediately trigger a second request.
    var minimumIntervalAfterMovement: TimeInterval = 60

    /// A snapshot older than this is shown as stale (dimmed / "last updated…")
    /// rather than presented as current, even if the fetch that produced it
    /// succeeded.
    var staleAfter: TimeInterval = 30 * 60

    /// Whether to fetch now, given the last successful fetch (if any) and the
    /// current coordinate/time. Pure — no clock reads, no I/O.
    func shouldRefresh(lastFetch: WeatherFetchRecord?, currentCoordinate: WeatherCoordinate, now: Date) -> Bool {
        guard let lastFetch else { return true }

        let elapsed = now.timeIntervalSince(lastFetch.date)
        guard elapsed >= 0 else { return false }   // clock stepped backwards — don't spuriously refetch

        if elapsed >= minimumInterval { return true }

        if elapsed >= minimumIntervalAfterMovement {
            let moved = lastFetch.coordinate.distance(to: currentCoordinate)
            if moved >= minimumMovementMeters { return true }
        }

        return false
    }
}

/// The coordinate + time of the last successful fetch — what `shouldRefresh`
/// compares against.
nonisolated struct WeatherFetchRecord: Equatable, Sendable {
    var coordinate: WeatherCoordinate
    var date: Date
}
