//
//  DeviceStatusStore.swift
//  Dash
//
//  The single source of truth on the iPad for **device / relay status** — the
//  iPhone's battery today, more relay fields later. Deliberately separate from
//  `LocationStore`: location and device telemetry are different contracts on the
//  wire (`LocationPacket` vs `DeviceStatusPacket`) and different concerns here.
//
//  Like `LocationStore`, it does NOT own the transport. `ConnectionCoordinator`
//  feeds it via `ingest(_:)` and calls `connectionEnded()` when a session stops.
//  The sidebar observes this object; it never parses network packets and
//  `DashboardShell` is not involved.
//
//  Freshness: battery status is quiet by nature (the relay only sends on a
//  meaningful change), so it does NOT go stale on a timer the way GPS does. It is
//  `.live` while connected with data, `.stale` if the session drops (last-known
//  value kept, shown de-emphasised) or if — while still connected — nothing
//  arrives for a long grace period, and `.unavailable` before the first value.
//

import Combine
import DashShared
import Foundation

@MainActor
final class DeviceStatusStore: ObservableObject {

    /// Whether the battery reading can be trusted right now.
    nonisolated enum Freshness: Equatable, Sendable {
        /// No device-status packet received yet (or never after a reconnect).
        case unavailable
        /// A recent packet on a live session.
        case live
        /// The session dropped, or nothing arrived for the grace period — the
        /// last-known value is kept but should read as possibly out of date.
        case stale
    }

    // MARK: - Observable state

    /// Battery charge `0...1`, or `nil` when unknown / never received.
    @Published private(set) var batteryLevel: Double?

    /// Battery charging state. `.unknown` until the first packet.
    @Published private(set) var batteryState: BatteryState = .unknown

    /// Freshness of the values above.
    @Published private(set) var freshness: Freshness = .unavailable

    // MARK: - Derived

    /// Whole-percent charge (`0...100`), or `nil` when unknown.
    var batteryPercent: Int? {
        batteryLevel.map { Int(($0 * 100).rounded()) }
    }

    /// Whether there is a usable battery reading to show (even if stale).
    var hasReading: Bool { batteryLevel != nil && freshness != .unavailable }

    // MARK: - Config

    /// While connected, if no device-status packet arrives within this window the
    /// reading is marked `.stale`. Generous — the relay only sends on change, and
    /// it resends on (re)connect.
    let graceInterval: TimeInterval

    private var lastUpdate: Date?
    private var watchdogTask: Task<Void, Never>?

    init(graceInterval: TimeInterval = 180) {
        self.graceInterval = graceInterval
    }

    deinit {
        watchdogTask?.cancel()
    }

    // MARK: - Ingestion

    /// Record a newly received device-status packet. `date` is injectable for
    /// tests; production callers use the arrival time.
    func ingest(_ status: DeviceStatusPacket, at date: Date = Date()) {
        batteryLevel = DeviceStatusPacket.normalise(status.batteryLevel)
        batteryState = status.batteryState
        lastUpdate = date
        freshness = .live
        armWatchdog()
    }

    /// Called by `ConnectionCoordinator` when the relay session ends. The
    /// last-known battery values are kept for display but flagged `.stale`
    /// (`.unavailable` if nothing was ever received).
    func connectionEnded() {
        watchdogTask?.cancel()
        watchdogTask = nil
        lastUpdate = nil
        freshness = (batteryLevel == nil) ? .unavailable : .stale
    }

    // MARK: - Watchdog

    /// Recompute `freshness` from how long ago the last packet arrived. Called by
    /// the watchdog task and, with an explicit `now`, by tests.
    func refreshFreshness(now current: Date = Date()) {
        guard let last = lastUpdate else {
            freshness = (batteryLevel == nil) ? .unavailable : .stale
            return
        }
        if current.timeIntervalSince(last) >= graceInterval {
            freshness = .stale
        }
    }

    private func armWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            guard let self else { return }
            let interval = self.graceInterval
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self.refreshFreshness()
        }
    }
}
