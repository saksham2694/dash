//
//  LocationStore.swift
//  Dash
//
//  The single source of truth for *received location data* on the iPad (spec §2):
//  the latest packet and a watchdog that flags when packets stop arriving
//  (spec §3.7).
//
//  It does NOT own the network transport or connection state — that moved up to
//  `ConnectionCoordinator`, which feeds this store via `ingest(_:)` and calls
//  `connectionEnded()` when a session stops. Every feature (map, speedometer,
//  trip computer) observes this object; none of them touch the network.
//

import Combine
import DashShared
import Foundation

@MainActor
final class LocationStore: ObservableObject {

    /// Whether fresh location data is arriving.
    enum Signal: Equatable {
        /// Nothing received yet, or the session has ended.
        case waiting
        /// Packets are arriving within the watchdog interval.
        case live
        /// A packet was received once, but none within `staleInterval` — the UI
        /// should show "GPS signal lost" rather than trust `latestPacket` (spec §3.7).
        case stale
    }

    // MARK: - Observable state

    /// The most recent packet received. Retained even when the signal goes stale
    /// so the UI can show last-known position instead of blanking out.
    @Published private(set) var latestPacket: LocationPacket?

    /// Watchdog state — drives the "signal lost" indicator.
    @Published private(set) var signal: Signal = .waiting

    // MARK: - Derived conveniences

    var hasFix: Bool { latestPacket != nil }
    var isSignalLost: Bool { signal == .stale }
    var speed: Double? { latestPacket?.speed }
    var heading: Double? { latestPacket?.heading }

    // MARK: - Config

    /// How long without a packet before the signal is considered lost (spec: ~5–10s).
    let staleInterval: TimeInterval

    private var watchdogTask: Task<Void, Never>?
    private var lastPacketDate: Date?

    init(staleInterval: TimeInterval = 7) {
        self.staleInterval = staleInterval
    }

    deinit {
        watchdogTask?.cancel()
    }

    // MARK: - Ingestion (main actor)

    /// Record a newly received packet. `date` is injectable for tests; production
    /// callers use the arrival time.
    func ingest(_ packet: LocationPacket, at date: Date = Date()) {
        latestPacket = packet
        lastPacketDate = date
        signal = .live
        armWatchdog()
    }

    /// Called by `ConnectionCoordinator` when the relay session ends (deliberate
    /// disconnect or teardown). Stops the watchdog and returns to `.waiting`; the
    /// last known packet is kept for display.
    func connectionEnded() {
        watchdogTask?.cancel()
        watchdogTask = nil
        lastPacketDate = nil
        signal = .waiting
    }

    // MARK: - Watchdog

    /// Recompute `signal` from how long ago the last packet arrived. Called by the
    /// watchdog task and, with an explicit `now`, by tests.
    func refreshSignal(now current: Date = Date()) {
        guard let last = lastPacketDate else {
            signal = .waiting
            return
        }
        signal = current.timeIntervalSince(last) >= staleInterval ? .stale : .live
    }

    private func armWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            guard let self else { return }
            let interval = self.staleInterval
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self.refreshSignal()
        }
    }
}
