//
//  WeatherViewModel.swift
//  Dash — Weather feature
//
//  The feature's app-scoped state: the latest `WeatherSnapshot`, fetch
//  bookkeeping, and the refresh policy that keeps `WeatherService` from being
//  hammered (M8.4 §2/§8). Every Weather view — full-screen and each widget
//  size — reads this one instance via `presentation(at:)`, so fetch/caching
//  logic is never duplicated per size.
//
//  `ObservableObject`, unlike `SpeedometerViewModel`: Weather has no per-frame
//  driver (no `TimelineView`) — views should simply re-render when a fetch
//  resolves, so `@Published` is the right tool here (the same reasoning
//  `LocationStore` and `MapViewModel` already use).
//
//  `locationDidChange(at:)` is cheap to call on every GPS packet (~1 Hz) — the
//  pure `WeatherRefreshPolicy` inside decides whether that actually reaches
//  the network, so the caller doesn't have to reason about throttling itself.
//

import Combine
import Foundation

@MainActor
final class WeatherViewModel: ObservableObject {

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isFetching = false

    /// Set only when a fetch has failed with no existing snapshot to fall
    /// back to (`WeatherPresentation.failed`). A failure WITH an existing
    /// snapshot instead marks that snapshot `stale` — see `presentation(at:)`.
    private var hasFailedWithNoData = false

    /// Whether the most recent fetch attempt failed (even though we still
    /// have an older snapshot to show, dimmed, until the next success).
    private var lastFetchFailed = false

    private let service: any WeatherService
    private let policy: WeatherRefreshPolicy
    private weak var locationSource: (any WeatherLocationSource)?
    private var lastFetch: WeatherFetchRecord?

    init(service: any WeatherService, policy: WeatherRefreshPolicy = WeatherRefreshPolicy()) {
        self.service = service
        self.policy = policy
    }

    /// Wire up the location source. Called from a Weather view's `.task` /
    /// `.onAppear` with the host's `LocationStore`. Idempotent.
    func connect(to locationSource: any WeatherLocationSource) {
        self.locationSource = locationSource
    }

    /// The host's location may have changed (a new GPS packet arrived, or the
    /// view just appeared). Async and directly awaitable so callers — and
    /// tests — see the fetch (if any) complete before this returns.
    func locationDidChange(at now: Date = Date()) async {
        guard let coordinate = locationSource?.currentCoordinate else { return }
        guard !isFetching else { return }
        guard policy.shouldRefresh(lastFetch: lastFetch, currentCoordinate: coordinate, now: now) else { return }
        await fetch(coordinate: coordinate, now: now)
    }

    private func fetch(coordinate: WeatherCoordinate, now: Date) async {
        isFetching = true
        defer { isFetching = false }

        do {
            let fetched = try await service.fetchWeather(latitude: coordinate.latitude, longitude: coordinate.longitude)
            snapshot = fetched
            lastFetch = WeatherFetchRecord(coordinate: coordinate, date: now)
            lastFetchFailed = false
            hasFailedWithNoData = false
        } catch {
            lastFetchFailed = true
            hasFailedWithNoData = (snapshot == nil)
        }
    }

    /// What to render at `now`. Pure read — never triggers a fetch.
    func presentation(at now: Date = Date()) -> WeatherPresentation {
        guard let snapshot else {
            if hasFailedWithNoData { return .failed }
            return isFetching ? .loading : .unavailable
        }
        let aged = now.timeIntervalSince(snapshot.fetchedAt) >= policy.staleAfter
        return .loaded(snapshot, stale: aged || lastFetchFailed)
    }
}
