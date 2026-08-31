//
//  LocationReceiving.swift
//  Dash
//
//  The seam between `ConnectionCoordinator` and the transport. `LocationReceiver`
//  is the real implementation (Bonjour discovery + TCP receive); tests inject a
//  stub so the connection/session state machine can be exercised without any
//  actual networking.
//

import DashShared
import Foundation

protocol LocationReceiving: AnyObject, Sendable {

    /// Called on the main actor for every decoded packet.
    var onPacket: (@MainActor @Sendable (LocationPacket) -> Void)? { get set }

    /// Called on the main actor whenever the transport's status changes.
    var onStatusChange: (@MainActor @Sendable (LocationReceiver.Status) -> Void)? { get set }

    /// Begin discovering + connecting.
    func start()

    /// Stop discovery + connection. A `LocationReceiving` must not auto-reconnect
    /// after this until `start()` is called again.
    func stop()
}

extension LocationReceiver: LocationReceiving {}
