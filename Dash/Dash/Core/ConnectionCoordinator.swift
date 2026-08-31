//
//  ConnectionCoordinator.swift
//  Dash
//
//  The connection/session layer for the iPad. It sits *above* the networking and
//  location layers:
//
//    • owns the `LocationReceiving` transport and its lifecycle
//    • translates the transport's phase into a stable `ConnectionState`
//    • forwards decoded packets into `LocationStore` (still the single source of
//      truth for location data — this type never stores packets)
//    • distinguishes a deliberate user disconnect from an incidental drop, and a
//      deliberate disconnect does not auto-reconnect
//
//  It does NOT own pairing/known-device state — that is `KnownDeviceStore`, which
//  is deliberately independent (see PROJECT_STATUS.md).
//

import Combine
import DashShared
import Foundation

@MainActor
final class ConnectionCoordinator: ObservableObject {

    /// The current link state. This is the single place the rest of the app reads
    /// connection state from.
    @Published private(set) var connectionState: ConnectionState = .disconnected

    /// Bonjour service name of the relay we're connected to, when connected.
    /// The hook a future pairing flow uses to remember a device.
    @Published private(set) var connectedDeviceName: String?

    /// True only while a live session to DashRelay exists. The dashboard is shown
    /// only when this is true.
    var isConnected: Bool { connectionState == .connected }

    private let receiver: any LocationReceiving
    private let locationStore: LocationStore

    /// Set when the user deliberately disconnects; cleared by `startSession()`.
    /// While set, trailing transport status updates are ignored so the state
    /// stays `.disconnected` and nothing reconnects on its own.
    private var deliberatelyDisconnected = false

    convenience init(locationStore: LocationStore) {
        self.init(receiver: LocationReceiver(), locationStore: locationStore)
    }

    init(receiver: any LocationReceiving, locationStore: LocationStore) {
        self.receiver = receiver
        self.locationStore = locationStore

        receiver.onPacket = { [weak self] packet in
            self?.locationStore.ingest(packet)
        }
        receiver.onStatusChange = { [weak self] status in
            self?.handleTransportStatus(status)
        }
    }

    // MARK: - Session control

    /// Start (or resume) trying to reach DashRelay.
    func startSession() {
        deliberatelyDisconnected = false
        receiver.start()
    }

    /// Deliberate user disconnect: tear the session down and stay down. Will not
    /// auto-reconnect until `startSession()` is called again.
    func disconnect() {
        deliberatelyDisconnected = true
        receiver.stop()
        connectionState = .disconnected
        connectedDeviceName = nil
        locationStore.connectionEnded()
    }

    // MARK: - Transport → app state

    private func handleTransportStatus(_ status: LocationReceiver.Status) {
        guard !deliberatelyDisconnected else { return }
        connectionState = Self.connectionState(for: status.phase)
        connectedDeviceName = status.connectedServiceName
    }

    /// Pure mapping from the transport's phase to the app-level state.
    static func connectionState(for phase: LocationReceiver.Status.Phase) -> ConnectionState {
        switch phase {
        case .stopped: .disconnected
        case .browsing: .discovering
        case .connecting: .connecting
        case .connected: .connected
        }
    }
}
