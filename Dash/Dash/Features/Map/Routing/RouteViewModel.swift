//
//  RouteViewModel.swift
//  Dash
//
//  Orchestrates routing: when the chosen destination changes, request driving
//  routes from the current vehicle position and expose a loading / success /
//  error / no-location `State`. M4.5: a successful request now carries a
//  `RouteOptions` (recommended route + alternatives).
//
//  Holds no SDK types, no `LocationStore`, and no GPS logic — the composing view
//  passes in the latest usable origin (`MapCoordinate?`) alongside the
//  destination, exactly as it already feeds `PlaceSearchViewModel.origin`.
//
//  Manual "Refresh Route" (M4.5) lives in a separate `refresh` field so the
//  existing preview / navigation UI stays put while a refresh runs, and the new
//  options are *offered* (never auto-applied). No timers, no automatic
//  rerouting.
//

import Combine
import Foundation

@MainActor
final class RouteViewModel: ObservableObject {

    enum State: Equatable {
        /// No destination — nothing to route.
        case idle
        /// A route request is in flight.
        case loading
        /// Routes are available (recommended + any alternatives).
        case loaded(RouteOptions)
        /// A destination is chosen but there is no usable current location, so no
        /// request was made (distinct from a request that failed).
        case noCurrentLocation
        /// The route request failed.
        case failed(RouteError)
    }

    /// A manual refresh pass, kept apart from `state` so the current route UI
    /// is not disrupted while it runs.
    enum Refresh: Equatable {
        /// No refresh in progress or pending.
        case none
        /// A refresh request is in flight.
        case recalculating
        /// Fresh options fetched — awaiting the driver's choice (or dismissal).
        case options(RouteOptions)
        /// Refresh needs a current location and there isn't one.
        case noCurrentLocation
        /// The refresh request failed.
        case failed(RouteError)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var refresh: Refresh = .none

    /// The active/last initial-route task — exposed so tests can await it.
    private(set) var currentTask: Task<Void, Never>?
    /// The active refresh task — exposed so tests can await it.
    private(set) var refreshTask: Task<Void, Never>?

    /// The destination the current routes were computed for — reused by
    /// `refreshRoutes` so a manual refresh keeps the same target.
    private(set) var destination: Destination?

    private let service: any RouteService

    init(service: any RouteService) {
        self.service = service
    }

    // MARK: - Initial request

    /// Request (or clear) routes for `destination`, from `origin`.
    ///
    /// - `destination == nil` → `.idle`, no request.
    /// - `origin == nil` → `.noCurrentLocation`, no request.
    /// - otherwise → `.loading`, then `.loaded` / `.failed`.
    ///
    /// Any in-flight request (and any pending refresh) is cancelled first. Also
    /// the Retry action — the caller passes the still-current destination and a
    /// fresh origin.
    func requestRoutes(to destination: Destination?, from origin: MapCoordinate?) {
        currentTask?.cancel()
        currentTask = nil
        cancelRefresh()

        self.destination = destination

        guard let destination else {
            state = .idle
            return
        }
        guard let origin else {
            state = .noCurrentLocation
            return
        }

        state = .loading
        let target = destination.coordinate
        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let routes = try await service.routes(from: origin, to: target)
                guard !Task.isCancelled else { return }
                guard let options = RouteOptions(routes) else {
                    state = .failed(.noRoute)
                    return
                }
                state = .loaded(options)
            } catch is CancellationError {
                return
            } catch let error as RouteError {
                state = .failed(error)
            } catch {
                state = .failed(.unavailable)
            }
        }
    }

    // MARK: - Manual refresh (M4.5)

    /// Fetch a fresh set of alternatives from the *current* `origin`, keeping the
    /// remembered `destination`. Result lands in `refresh` (never `state`), so
    /// the current route stays active until the driver picks a new one.
    func refreshRoutes(from origin: MapCoordinate?) {
        refreshTask?.cancel()
        refreshTask = nil

        guard let destination else { return } // nothing to refresh

        guard let origin else {
            refresh = .noCurrentLocation
            return
        }

        refresh = .recalculating
        let target = destination.coordinate
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let routes = try await service.routes(from: origin, to: target)
                guard !Task.isCancelled else { return }
                guard let options = RouteOptions(routes) else {
                    refresh = .failed(.noRoute)
                    return
                }
                refresh = .options(options)
            } catch is CancellationError {
                return
            } catch let error as RouteError {
                refresh = .failed(error)
            } catch {
                refresh = .failed(.unavailable)
            }
        }
    }

    /// Dismiss a refresh result / error — the driver kept the current route.
    func clearRefresh() {
        cancelRefresh()
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refresh = .none
    }
}
