//
//  RouteViewModel.swift
//  Dash
//
//  Orchestrates M3 routing: when the chosen destination changes, request a
//  driving route from the current vehicle position and expose a loading /
//  success / error / no-location `State`.
//
//  Holds no SDK types, no `LocationStore`, and no GPS logic — the composing view
//  passes in the latest usable origin (`MapCoordinate?`) alongside the
//  destination, exactly as it already feeds `PlaceSearchViewModel.origin`. It
//  does not auto-reroute; a fresh request only happens on an explicit
//  `requestRoute(...)` call (destination change or a Retry).
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
        /// A route is available.
        case loaded(Route)
        /// A destination is chosen but there is no usable current location, so no
        /// request was made (distinct from a request that failed).
        case noCurrentLocation
        /// The route request failed.
        case failed(RouteError)
    }

    @Published private(set) var state: State = .idle

    /// The active/last route task — exposed so tests can await completion.
    private(set) var currentTask: Task<Void, Never>?

    private let service: any RouteService

    init(service: any RouteService) {
        self.service = service
    }

    /// Request (or clear) the route for `destination`, from `origin`.
    ///
    /// - `destination == nil` → `.idle`, no request.
    /// - `origin == nil` → `.noCurrentLocation`, no request (fail gracefully
    ///   rather than send an invalid request).
    /// - otherwise → `.loading`, then `.loaded` / `.failed`.
    ///
    /// Any in-flight request is cancelled first. Also used as the Retry action —
    /// the caller passes the still-current destination and a fresh origin.
    func requestRoute(to destination: Destination?, from origin: MapCoordinate?) {
        currentTask?.cancel()
        currentTask = nil

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
                let route = try await service.route(from: origin, to: target)
                guard !Task.isCancelled else { return }
                state = .loaded(route)
            } catch is CancellationError {
                return
            } catch let error as RouteError {
                state = .failed(error)
            } catch {
                state = .failed(.unavailable)
            }
        }
    }
}
