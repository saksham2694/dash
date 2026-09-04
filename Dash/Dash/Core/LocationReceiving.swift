//
//  LocationReceiving.swift
//  Dash
//
//  The seam between `ConnectionCoordinator` and the transport. `LocationReceiver`
//  is the real implementation (Bonjour discovery + TCP receive); tests inject a
//  stub so the connection/pairing state machine can be exercised without any
//  actual networking.
//
//  Discovery and connection are now separate operations: `start()` only browses,
//  and the coordinator decides *which* discovered relay to connect to with
//  `setTargetRelay(id:)`. There is no "connect to the first result" behaviour.
//

import DashShared
import Foundation

protocol LocationReceiving: AnyObject, Sendable {

    /// Called on the main actor for every decoded GPS packet.
    var onPacket: (@MainActor @Sendable (LocationPacket) -> Void)? { get set }

    /// Called on the main actor for every decoded device-status packet.
    var onDeviceStatus: (@MainActor @Sendable (DeviceStatusPacket) -> Void)? { get set }

    /// Called on the main actor whenever the transport's status changes.
    var onStatusChange: (@MainActor @Sendable (LocationReceiver.Status) -> Void)? { get set }

    /// Called on the main actor whenever the set of visible DashRelay instances
    /// changes while browsing.
    var onDiscoveryChange: (@MainActor @Sendable ([DiscoveredRelay]) -> Void)? { get set }

    /// Begin browsing for DashRelay instances. Does **not** connect on its own —
    /// a target must be set via `setTargetRelay(id:)`.
    func start()

    /// Stop browsing and drop any connection. A `LocationReceiving` must not
    /// auto-reconnect after this until `start()` is called again. Clears the
    /// target relay.
    func stop()

    /// Pin the transport to the relay with this stable id: connect to it when it
    /// is (or becomes) visible, and reconnect only to it after an incidental
    /// drop. Passing `nil` clears the target and drops any current connection,
    /// but keeps browsing. Passing a *different* id than the one currently
    /// connected also drops the current connection.
    func setTargetRelay(id: String?)
}

extension LocationReceiver: LocationReceiving {}
