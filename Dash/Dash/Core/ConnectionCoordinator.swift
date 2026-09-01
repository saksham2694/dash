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
//    • bridges *pairing* (a persisted relationship, owned by `KnownDeviceStore`)
//      to *connection* (this session): it prefers the paired relay, never
//      auto-connects to an unrelated one, and offers the discovered list for a
//      first-time pick.
//
//  Pairing persistence stays in `KnownDeviceStore`; discovery/TCP stays in
//  `LocationReceiver`. This type only decides *which* relay the transport targets
//  and *when*.
//

import Combine
import DashShared
import Foundation

@MainActor
final class ConnectionCoordinator: ObservableObject {

    /// The current link state. The single place the rest of the app reads
    /// connection state from.
    @Published private(set) var connectionState: ConnectionState = .disconnected

    /// Stable id of the relay we're connected to, when connected.
    @Published private(set) var connectedRelayID: String?

    /// The connected relay's human-readable name, when connected.
    @Published private(set) var connectedDisplayName: String?

    /// DashRelay instances currently visible on the network (while browsing).
    @Published private(set) var discoveredRelays: [DiscoveredRelay] = []

    /// True only while a live session to DashRelay exists. The dashboard is shown
    /// only when this is true.
    var isConnected: Bool { connectionState == .connected }

    private let receiver: any LocationReceiving
    private let locationStore: LocationStore
    private let knownDevices: any KnownDeviceStoring

    /// Set when the user deliberately disconnects; cleared by `startSession()`.
    /// While set, trailing transport status / discovery updates are ignored so
    /// nothing reconnects on its own.
    private var deliberatelyDisconnected = false

    convenience init(locationStore: LocationStore, knownDevices: any KnownDeviceStoring) {
        self.init(receiver: LocationReceiver(), locationStore: locationStore, knownDevices: knownDevices)
    }

    init(
        receiver: any LocationReceiving,
        locationStore: LocationStore,
        knownDevices: any KnownDeviceStoring
    ) {
        self.receiver = receiver
        self.locationStore = locationStore
        self.knownDevices = knownDevices

        receiver.onPacket = { [weak self] packet in
            self?.locationStore.ingest(packet)
        }
        receiver.onStatusChange = { [weak self] status in
            self?.handleTransportStatus(status)
        }
        receiver.onDiscoveryChange = { [weak self] relays in
            self?.handleDiscovery(relays)
        }
    }

    // MARK: - Pairing-aware view state

    /// The paired relay Dash is waiting for but cannot currently see, if any.
    /// Drives the "Looking for <your iPhone>…" message. `nil` when there is no
    /// pairing, when the paired relay is visible, or once connected.
    var pairedRelayName: String? {
        guard !isConnected, let paired = knownDevices.pairedRelay else { return nil }
        return paired.displayName
    }

    /// The friendly name the user gave the paired relay, regardless of connection
    /// state. Drives the connected-state control on the dashboard. `nil` when
    /// nothing is paired.
    var pairedRelayDisplayName: String? { knownDevices.pairedRelay?.displayName }

    /// Relays to offer as a first-time pairing choice. Empty once a device is
    /// paired — we never invite the user to switch to a nearby stranger.
    var offerableRelays: [DiscoveredRelay] {
        guard knownDevices.pairedRelay == nil else { return [] }
        return discoveredRelays
    }

    // MARK: - Session control

    /// Start (or resume) trying to reach DashRelay. Prefers the paired relay.
    func startSession() {
        deliberatelyDisconnected = false
        receiver.start()
        updateTargetFromPairing()
    }

    /// Deliberate user disconnect: tear the session down and stay down. Keeps the
    /// pairing — this is not "forget". Will not auto-reconnect until
    /// `startSession()` is called again.
    func disconnect() {
        deliberatelyDisconnected = true
        receiver.stop()
        connectionState = .disconnected
        connectedRelayID = nil
        connectedDisplayName = nil
        discoveredRelays = []
        locationStore.connectionEnded()
    }

    /// First-time flow: the user picked a relay from the discovered list. Remember
    /// it (pairing) and connect to it (session).
    ///
    /// `customName` is the friendly name the user typed during pairing; it is
    /// stored as the `KnownRelay`'s display name. Blank/whitespace falls back to
    /// the relay's advertised name. The stable identity (`relay.id`) is never
    /// affected by the name.
    func pairAndConnect(to relay: DiscoveredRelay, named customName: String? = nil) {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? relay.displayName : trimmed
        knownDevices.remember(KnownRelay(id: relay.id, displayName: name))
        deliberatelyDisconnected = false
        receiver.start()
        receiver.setTargetRelay(id: relay.id)
    }

    /// Forget the currently paired relay. This removes the *relationship*, not
    /// just the session: afterwards Dash behaves like a first-time setup —
    /// browsing and offering whatever it finds. Any live session to that relay is
    /// dropped (forgetting implies no auto-reconnect to it).
    func forgetPairedRelay() {
        guard let paired = knownDevices.pairedRelay else { return }
        knownDevices.forget(paired)

        // Clear the transport's target (drops the connection if it was to the
        // now-forgotten relay) but keep browsing so the picker can repopulate.
        receiver.setTargetRelay(id: nil)
        connectedRelayID = nil
        connectedDisplayName = nil
        locationStore.connectionEnded()
        deliberatelyDisconnected = false
        connectionState = .discovering
        receiver.start()
        updateTargetFromPairing()
    }

    // MARK: - Pairing → transport target

    /// Point the transport at the paired relay when we can identify one
    /// unambiguously.
    private func updateTargetFromPairing() {
        guard !deliberatelyDisconnected, !isConnected else { return }
        let known = knownDevices.knownDevices
        if known.count == 1 {
            receiver.setTargetRelay(id: known[0].id)
        } else {
            // 0 known → first-time (no target, user picks).
            // >1 known → wait until exactly one is visible (handled in discovery).
            receiver.setTargetRelay(id: nil)
        }
    }

    // MARK: - Transport → app state

    private func handleDiscovery(_ relays: [DiscoveredRelay]) {
        guard !deliberatelyDisconnected else { return }
        discoveredRelays = relays

        guard !isConnected, connectionState != .connecting else { return }
        let knownIDs = Set(knownDevices.knownDevices.map(\.id))
        let visibleKnown = relays.filter { knownIDs.contains($0.id) }
        // Auto-connect only when there is exactly one known relay in view. A
        // discovered stranger is never targeted.
        if visibleKnown.count == 1 {
            receiver.setTargetRelay(id: visibleKnown[0].id)
        }
    }

    private func handleTransportStatus(_ status: LocationReceiver.Status) {
        guard !deliberatelyDisconnected else { return }
        connectionState = Self.connectionState(for: status.phase)
        connectedRelayID = status.connectedRelayID
        connectedDisplayName = status.connectedDisplayName
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
