//
//  LocationStore.swift
//  Dash
//
//  The single source of truth for location on the iPad (spec §2). `LocationReceiver`
//  owns the network; `LocationStore` owns app-level state: the latest packet, the
//  link phase, and a watchdog that flags when packets stop arriving (spec §3.7).
//
//  Every feature (map, speedometer, trip computer) will observe this object — none
//  of them touch `LocationReceiver` or the network directly.
//

import Combine
import DashShared
import Foundation

@MainActor
final class LocationStore: ObservableObject {

    /// Whether fresh location data is arriving.
    enum Signal: Equatable {
        /// Nothing received yet, or the store is stopped.
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

    /// Where the underlying network link is (searching / connecting / connected).
    @Published private(set) var linkPhase: LocationReceiver.Status.Phase = .stopped

    // MARK: - Derived conveniences

    var hasFix: Bool { latestPacket != nil }
    var isSignalLost: Bool { signal == .stale }
    var speed: Double? { latestPacket?.speed }
    var heading: Double? { latestPacket?.heading }

    // MARK: - Config / collaborators

    /// How long without a packet before the signal is considered lost (spec: ~5–10s).
    let staleInterval: TimeInterval

    private let receiver: LocationReceiver
    private var watchdogTask: Task<Void, Never>?
    private var lastPacketDate: Date?

    convenience init(staleInterval: TimeInterval = 7) {
        self.init(receiver: LocationReceiver(), staleInterval: staleInterval)
    }

    init(receiver: LocationReceiver, staleInterval: TimeInterval = 7) {
        self.receiver = receiver
        self.staleInterval = staleInterval

        receiver.onPacket = { [weak self] packet in
            self?.ingest(packet)
        }
        receiver.onStatusChange = { [weak self] status in
            self?.updateLinkPhase(status.phase)
        }
    }

    deinit {
        watchdogTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Start receiving. Delegates networking to `LocationReceiver`.
    func start() {
        receiver.start()
    }

    /// Stop receiving and reset the watchdog. `latestPacket` is kept as last-known.
    func stop() {
        receiver.stop()
        watchdogTask?.cancel()
        watchdogTask = nil
        signal = .waiting
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

    private func updateLinkPhase(_ phase: LocationReceiver.Status.Phase) {
        linkPhase = phase
        // A brief drop (red light, roaming) shouldn't panic the UI — the watchdog
        // decides staleness. Only a full stop with nothing received resets to waiting.
        if phase == .stopped, latestPacket == nil {
            signal = .waiting
        }
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
