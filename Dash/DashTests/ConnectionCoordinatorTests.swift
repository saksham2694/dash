//
//  ConnectionCoordinatorTests.swift
//  DashTests
//
//  The connection/pairing state machine, driven through a stub transport — no
//  real Bonjour or TCP. Covers first-time pairing, preferring the paired relay,
//  ignoring unrelated relays, Disconnect vs Forget, and the sticky deliberate
//  disconnect.
//

import Foundation
import Testing
@testable import Dash
import DashShared

/// Stub `LocationReceiving`: records lifecycle + target calls, lets the test
/// drive the status / packet / discovery callbacks.
final class StubLocationReceiver: LocationReceiving, @unchecked Sendable {
    var onPacket: (@MainActor @Sendable (LocationPacket) -> Void)?
    var onStatusChange: (@MainActor @Sendable (LocationReceiver.Status) -> Void)?
    var onDiscoveryChange: (@MainActor @Sendable ([DiscoveredRelay]) -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var targetCalls: [String?] = []

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func setTargetRelay(id: String?) { targetCalls.append(id) }

    @MainActor func emit(status: LocationReceiver.Status) { onStatusChange?(status) }
    @MainActor func emit(packet: LocationPacket) { onPacket?(packet) }
    @MainActor func emit(discovery: [DiscoveredRelay]) { onDiscoveryChange?(discovery) }
}

@MainActor
@Suite("ConnectionCoordinator")
struct ConnectionCoordinatorTests {

    // MARK: - Fixtures

    private func makeStore() -> KnownDeviceStore {
        KnownDeviceStore(defaults: UserDefaults(suiteName: "cc-test-\(UUID().uuidString)")!)
    }

    private func makeSUT(
        known: [KnownRelay] = []
    ) -> (ConnectionCoordinator, StubLocationReceiver, LocationStore, KnownDeviceStore) {
        let receiver = StubLocationReceiver()
        let store = LocationStore()
        let knownStore = makeStore()
        for device in known { knownStore.remember(device) }
        let coordinator = ConnectionCoordinator(receiver: receiver, locationStore: store, knownDevices: knownStore)
        return (coordinator, receiver, store, knownStore)
    }

    private func relay(_ id: String, _ name: String) -> DiscoveredRelay {
        DiscoveredRelay(id: id, displayName: name)
    }

    private func known(_ id: String, _ name: String) -> KnownRelay {
        KnownRelay(id: id, displayName: name)
    }

    private func connected(_ id: String, _ name: String) -> LocationReceiver.Status {
        .init(phase: .connected, connectedRelayID: id, connectedDisplayName: name)
    }

    private func packet(latitude: Double = 1) -> LocationPacket {
        LocationPacket(
            latitude: latitude, longitude: 2, speed: 0, heading: -1,
            timestamp: Date(timeIntervalSince1970: 1_756_700_000)
        )
    }

    // MARK: - Basic transitions

    @Test("starts disconnected")
    func initialState() {
        let (coordinator, _, _, _) = makeSUT()
        #expect(coordinator.connectionState == .disconnected)
        #expect(coordinator.isConnected == false)
    }

    @Test("disconnected → discovering when the session starts")
    func disconnectedToDiscovering() {
        let (coordinator, receiver, _, _) = makeSUT()

        coordinator.startSession()
        #expect(receiver.startCount == 1)

        receiver.emit(status: .init(phase: .browsing))
        #expect(coordinator.connectionState == .discovering)
    }

    @Test("discovering → connecting → connected, exposing relay id + name")
    func throughToConnected() {
        let (coordinator, receiver, _, _) = makeSUT()
        coordinator.startSession()

        receiver.emit(status: .init(phase: .connecting))
        #expect(coordinator.connectionState == .connecting)

        receiver.emit(status: connected("relay-1", "Saksham's iPhone"))
        #expect(coordinator.connectionState == .connected)
        #expect(coordinator.isConnected)
        #expect(coordinator.connectedRelayID == "relay-1")
        #expect(coordinator.connectedDisplayName == "Saksham's iPhone")
    }

    @Test("connected → discovering when the transport drops back to browsing")
    func connectedToDiscovering() {
        let (coordinator, receiver, _, _) = makeSUT()
        coordinator.startSession()
        receiver.emit(status: connected("relay-1", "iPhone"))
        #expect(coordinator.isConnected)

        receiver.emit(status: .init(phase: .browsing))
        #expect(coordinator.connectionState == .discovering)
        #expect(coordinator.isConnected == false)
    }

    @Test("phase → connection state mapping")
    func phaseMapping() {
        #expect(ConnectionCoordinator.connectionState(for: .stopped) == .disconnected)
        #expect(ConnectionCoordinator.connectionState(for: .browsing) == .discovering)
        #expect(ConnectionCoordinator.connectionState(for: .connecting) == .connecting)
        #expect(ConnectionCoordinator.connectionState(for: .connected) == .connected)
    }

    // MARK: - LocationStore feeding

    @Test("decoded packets flow into LocationStore, not into the coordinator")
    func packetsFlowToStore() {
        let (coordinator, receiver, store, _) = makeSUT()
        let p = packet(latitude: 7)

        withExtendedLifetime(coordinator) {
            receiver.emit(packet: p)
            #expect(store.latestPacket == p)
            #expect(store.signal == .live)
        }
    }

    @Test("deliberate disconnect resets the LocationStore signal")
    func disconnectResetsStoreSignal() {
        let (coordinator, receiver, store, _) = makeSUT()
        coordinator.startSession()
        receiver.emit(packet: packet())
        #expect(store.signal == .live)

        coordinator.disconnect()
        #expect(store.signal == .waiting)
    }

    // MARK: - First-time pairing

    @Test("multiple discovered relays are surfaced, none auto-chosen")
    func multipleDiscoveredRelays() {
        let (coordinator, receiver, _, _) = makeSUT()
        coordinator.startSession()

        let a = relay("relay-a", "iPhone A")
        let b = relay("relay-b", "iPhone B")
        receiver.emit(discovery: [a, b])

        #expect(coordinator.discoveredRelays == [a, b])
        #expect(coordinator.offerableRelays == [a, b])
        // No relay was targeted for connection — the user must pick.
        #expect(receiver.targetCalls.compactMap { $0 }.isEmpty)
    }

    @Test("selecting a relay targets it and persists the pairing")
    func selectingARelayPairsAndConnects() {
        let (coordinator, receiver, _, knownStore) = makeSUT()
        coordinator.startSession()
        let b = relay("relay-b", "iPhone B")
        receiver.emit(discovery: [relay("relay-a", "iPhone A"), b])

        coordinator.pairAndConnect(to: b)

        #expect(receiver.targetCalls.last == "relay-b")
        #expect(knownStore.knownDevices.map(\.id) == ["relay-b"])
        #expect(knownStore.pairedRelay?.displayName == "iPhone B")
    }

    @Test("a friendly name given at pairing is stored; the stable id is unchanged")
    func pairingWithAFriendlyName() {
        let (coordinator, receiver, _, knownStore) = makeSUT()
        let b = relay("relay-b", "iPhone")   // generic advertised name

        coordinator.pairAndConnect(to: b, named: "  Sak’s iPhone  ")

        #expect(knownStore.pairedRelay?.id == "relay-b")            // identity untouched
        #expect(knownStore.pairedRelay?.displayName == "Sak’s iPhone")  // trimmed friendly name
        #expect(coordinator.pairedRelayDisplayName == "Sak’s iPhone")
        #expect(receiver.targetCalls.last == "relay-b")
    }

    @Test("a blank friendly name falls back to the relay's advertised name")
    func pairingWithABlankNameFallsBack() {
        let (coordinator, _, _, knownStore) = makeSUT()

        coordinator.pairAndConnect(to: relay("relay-b", "iPhone B"), named: "   ")

        #expect(knownStore.pairedRelay?.displayName == "iPhone B")

        // Nil name (the default) behaves the same.
        let (coordinator2, _, _, knownStore2) = makeSUT()
        coordinator2.pairAndConnect(to: relay("relay-c", "iPhone C"))
        #expect(knownStore2.pairedRelay?.displayName == "iPhone C")
    }

    @Test("the friendly name is exposed while connected too, for the dashboard control")
    func pairedNameAvailableWhileConnected() {
        let (coordinator, receiver, _, _) = makeSUT()
        coordinator.pairAndConnect(to: relay("relay-b", "iPhone"), named: "Sak’s iPhone")
        receiver.emit(status: connected("relay-b", "iPhone"))

        #expect(coordinator.isConnected)
        // pairedRelayName is suppressed while connected (setup screen not shown)...
        #expect(coordinator.pairedRelayName == nil)
        // ...but pairedRelayDisplayName is not — it drives ConnectedControlView.
        #expect(coordinator.pairedRelayDisplayName == "Sak’s iPhone")
    }

    @Test("a paired relay persists across store instances")
    func pairingPersists() {
        let suite = UserDefaults(suiteName: "cc-persist-\(UUID().uuidString)")!
        let knownStore = KnownDeviceStore(defaults: suite)
        let coordinator = ConnectionCoordinator(
            receiver: StubLocationReceiver(), locationStore: LocationStore(), knownDevices: knownStore
        )

        coordinator.pairAndConnect(to: relay("relay-x", "iPhone X"))

        let reloaded = KnownDeviceStore(defaults: suite)
        #expect(reloaded.knownDevices.map(\.id) == ["relay-x"])
    }

    // MARK: - Subsequent launches

    @Test("a paired relay is preferred automatically on startSession")
    func prefersPairedRelay() {
        let (coordinator, receiver, _, _) = makeSUT(known: [known("paired-1", "My iPhone")])

        coordinator.startSession()
        #expect(receiver.targetCalls == ["paired-1"])

        receiver.emit(status: .init(phase: .connecting))
        receiver.emit(status: connected("paired-1", "My iPhone"))
        #expect(coordinator.isConnected)
        #expect(coordinator.connectedRelayID == "paired-1")
    }

    @Test("an unrelated nearby relay is never targeted when a device is paired")
    func ignoresUnrelatedRelay() {
        let (coordinator, receiver, _, _) = makeSUT(known: [known("paired-1", "My iPhone")])
        coordinator.startSession()
        receiver.emit(status: .init(phase: .browsing))

        receiver.emit(discovery: [relay("stranger", "Someone else's iPhone")])

        #expect(receiver.targetCalls == ["paired-1"])   // stranger never targeted
        #expect(coordinator.connectionState == .discovering)
        #expect(coordinator.isConnected == false)
    }

    @Test("paired relay unavailable: keeps looking, offers no stranger")
    func pairedRelayUnavailable() {
        let (coordinator, receiver, _, _) = makeSUT(known: [known("paired-1", "My iPhone")])
        coordinator.startSession()
        receiver.emit(status: .init(phase: .browsing))
        receiver.emit(discovery: [relay("stranger", "Someone else's iPhone")])

        #expect(coordinator.pairedRelayName == "My iPhone")
        #expect(coordinator.offerableRelays.isEmpty)
        #expect(coordinator.connectionState == .discovering)
    }

    // MARK: - Disconnect vs Forget

    @Test("Disconnect ends the session but keeps the pairing")
    func disconnectPreservesPairing() {
        let (coordinator, receiver, _, knownStore) = makeSUT(known: [known("paired-1", "My iPhone")])
        coordinator.startSession()
        receiver.emit(status: connected("paired-1", "My iPhone"))

        coordinator.disconnect()

        #expect(coordinator.connectionState == .disconnected)
        #expect(receiver.stopCount == 1)
        #expect(knownStore.knownDevices.map(\.id) == ["paired-1"])   // still paired
        #expect(coordinator.pairedRelayName == "My iPhone")
    }

    @Test("a deliberate disconnect does not immediately reconnect")
    func deliberateDisconnectDoesNotReconnect() {
        let (coordinator, receiver, _, _) = makeSUT(known: [known("paired-1", "My iPhone")])
        coordinator.startSession()
        receiver.emit(status: connected("paired-1", "My iPhone"))

        coordinator.disconnect()

        // Trailing transport status *and* a fresh sighting of the paired relay
        // must both be ignored.
        receiver.emit(status: .init(phase: .browsing))
        receiver.emit(status: .init(phase: .connecting))
        receiver.emit(discovery: [relay("paired-1", "My iPhone")])

        #expect(coordinator.connectionState == .disconnected)
        #expect(receiver.startCount == 1)   // never restarted on its own
    }

    @Test("after a deliberate disconnect the user can start a new connection")
    func canReconnectAfterDisconnect() {
        let (coordinator, receiver, _, _) = makeSUT(known: [known("paired-1", "My iPhone")])
        coordinator.startSession()
        coordinator.disconnect()

        coordinator.startSession()
        #expect(receiver.startCount == 2)
        #expect(receiver.targetCalls.last == "paired-1")

        receiver.emit(status: .init(phase: .connecting))
        #expect(coordinator.connectionState == .connecting)
    }

    @Test("Forget removes the pairing and returns to first-time behaviour")
    func forgetRemovesPairing() {
        let (coordinator, receiver, _, knownStore) = makeSUT(known: [known("paired-1", "My iPhone")])
        coordinator.startSession()
        receiver.emit(status: connected("paired-1", "My iPhone"))

        coordinator.forgetPairedRelay()

        #expect(knownStore.knownDevices.isEmpty)
        #expect(coordinator.pairedRelayName == nil)
        #expect(coordinator.connectedRelayID == nil)
        #expect(coordinator.connectionState == .discovering)
        #expect(receiver.targetCalls.last == .some(nil))   // last target request cleared it

        // Now behaves like a first-time setup: discovered relays become offerable.
        receiver.emit(discovery: [relay("stranger", "Someone")])
        #expect(coordinator.offerableRelays.map(\.id) == ["stranger"])
    }

    // MARK: - Pairing vs connection are distinct concerns

    @Test("remembering a device does not change connection state; connecting does not pair")
    func pairingIndependentOfConnection() {
        let (coordinator, receiver, _, knownStore) = makeSUT()

        knownStore.remember(known("relay-1", "iPhone"))
        #expect(coordinator.connectionState == .disconnected)

        coordinator.startSession()
        receiver.emit(status: connected("relay-1", "iPhone"))
        #expect(coordinator.isConnected)
        #expect(knownStore.knownDevices.count == 1)   // connecting added nothing

        knownStore.forgetAll()
        #expect(coordinator.isConnected)   // forgetting did not drop the live link here
    }
}
