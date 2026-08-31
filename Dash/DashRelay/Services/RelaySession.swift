//
//  RelaySession.swift
//  DashRelay
//
//  The connection/session layer for the iPhone. It sits *above* the GPS and
//  networking layers:
//
//    • owns `LocationTracker` (GPS) and `LocationBroadcaster` (advertising/sending)
//      and wires each fix straight through
//    • exposes a session state that distinguishes "ready / waiting for a dashboard"
//      from "a dashboard is connected"
//    • the session controls when GPS tracking runs: `start()` begins it, `stop()`
//      (a deliberate disconnect) ends both networking and GPS
//    • a deliberate `stop()` does not auto-restart — nothing reconnects until
//      `start()` is called again
//

import Combine
import DashShared
import Foundation

// MARK: - Injectable seams (real types conform; tests use stubs)

@MainActor
protocol RelayTracking: AnyObject {
    var onPacket: ((LocationPacket) -> Void)? { get set }
    func start()
    func stop()
}

protocol RelayBroadcasting: AnyObject, Sendable {
    var onStatusChange: (@MainActor @Sendable (LocationBroadcaster.Status) -> Void)? { get set }
    func start()
    func stop()
    func broadcast(_ packet: LocationPacket)
}

extension LocationTracker: RelayTracking {}
extension LocationBroadcaster: RelayBroadcasting {}

// MARK: - Session controller

@MainActor
final class RelaySessionController: ObservableObject {

    enum State: Equatable {
        /// Not advertising, not tracking. Where a deliberate disconnect lands.
        case stopped
        /// Advertising via Bonjour and tracking GPS, but no dashboard connected yet.
        case waiting
        /// At least one dashboard is connected and receiving GPS.
        case connected
    }

    @Published private(set) var state: State = .stopped

    /// Whether `LocationTracker` is currently running. Mirrors the session:
    /// tracking runs from `start()` to `stop()`.
    @Published private(set) var isTrackingLocation = false

    private let tracker: any RelayTracking
    private let broadcaster: any RelayBroadcasting

    convenience init() {
        self.init(tracker: LocationTracker(), broadcaster: LocationBroadcaster())
    }

    init(tracker: any RelayTracking, broadcaster: any RelayBroadcasting) {
        self.tracker = tracker
        self.broadcaster = broadcaster

        // Every GPS fix goes straight to the broadcaster, in the same callback.
        tracker.onPacket = { [broadcaster] packet in
            broadcaster.broadcast(packet)
        }
        broadcaster.onStatusChange = { [weak self] status in
            self?.handleBroadcasterStatus(status)
        }
    }

    // MARK: - Session control

    /// Begin advertising and tracking GPS. Explicit "go"; idempotent.
    func start() {
        guard state == .stopped else { return }
        broadcaster.start()
        tracker.start()
        isTrackingLocation = true
        state = .waiting
    }

    /// Deliberate disconnect: stop networking AND GPS. Nothing reconnects until
    /// `start()` is called again.
    func stop() {
        broadcaster.stop()
        tracker.stop()
        isTrackingLocation = false
        state = .stopped
    }

    // MARK: - Broadcaster → session state

    private func handleBroadcasterStatus(_ status: LocationBroadcaster.Status) {
        // Ignore trailing updates after a deliberate stop.
        guard state != .stopped else { return }
        state = status.clientCount > 0 ? .connected : .waiting
    }
}
