//
//  ConnectionCoordinatorTests.swift
//  DashTests
//
//  The connection/session state machine, driven through a stub transport — no
//  real Bonjour or TCP.
//

import Foundation
import Testing
@testable import Dash
import DashShared

/// Stub `LocationReceiving`: records lifecycle calls, lets the test drive the
/// status/packet callbacks.
final class StubLocationReceiver: LocationReceiving, @unchecked Sendable {
    var onPacket: (@MainActor @Sendable (LocationPacket) -> Void)?
    var onStatusChange: (@MainActor @Sendable (LocationReceiver.Status) -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }

    @MainActor func emit(_ status: LocationReceiver.Status) { onStatusChange?(status) }
    @MainActor func emit(_ packet: LocationPacket) { onPacket?(packet) }
}

@MainActor
@Suite("ConnectionCoordinator")
struct ConnectionCoordinatorTests {

    private func makeSUT() -> (ConnectionCoordinator, StubLocationReceiver, LocationStore) {
        let receiver = StubLocationReceiver()
        let store = LocationStore()
        let coordinator = ConnectionCoordinator(receiver: receiver, locationStore: store)
        return (coordinator, receiver, store)
    }

    private func packet(latitude: Double = 1, longitude: Double = 2) -> LocationPacket {
        LocationPacket(
            latitude: latitude, longitude: longitude,
            speed: 0, heading: -1,
            timestamp: Date(timeIntervalSince1970: 1_756_700_000)
        )
    }

    // MARK: - Transitions

    @Test("starts disconnected")
    func initialState() {
        let (coordinator, _, _) = makeSUT()
        #expect(coordinator.connectionState == .disconnected)
        #expect(coordinator.isConnected == false)
    }

    @Test("disconnected → discovering when the session starts")
    func disconnectedToDiscovering() {
        let (coordinator, receiver, _) = makeSUT()

        coordinator.startSession()
        #expect(receiver.startCount == 1)

        receiver.emit(.init(phase: .browsing, discoveredServiceCount: 0))
        #expect(coordinator.connectionState == .discovering)
    }

    @Test("discovering → connecting")
    func discoveringToConnecting() {
        let (coordinator, receiver, _) = makeSUT()
        coordinator.startSession()
        receiver.emit(.init(phase: .browsing, discoveredServiceCount: 1))

        receiver.emit(.init(phase: .connecting, discoveredServiceCount: 1))
        #expect(coordinator.connectionState == .connecting)
    }

    @Test("connecting → connected, exposing the device name")
    func connectingToConnected() {
        let (coordinator, receiver, _) = makeSUT()
        coordinator.startSession()
        receiver.emit(.init(phase: .connecting, discoveredServiceCount: 1))

        receiver.emit(.init(phase: .connected, discoveredServiceCount: 1, connectedServiceName: "Saksham's iPhone"))
        #expect(coordinator.connectionState == .connected)
        #expect(coordinator.isConnected)
        #expect(coordinator.connectedDeviceName == "Saksham's iPhone")
    }

    @Test("connected → disconnected path (transport drops back to browsing)")
    func connectedToDisconnected() {
        let (coordinator, receiver, _) = makeSUT()
        coordinator.startSession()
        receiver.emit(.init(phase: .connected, discoveredServiceCount: 1, connectedServiceName: "iPhone"))
        #expect(coordinator.isConnected)

        receiver.emit(.init(phase: .browsing, discoveredServiceCount: 0))
        #expect(coordinator.connectionState == .discovering)
        #expect(coordinator.isConnected == false)
    }

    // MARK: - Deliberate disconnect

    @Test("deliberate disconnect stops the transport and stays disconnected")
    func deliberateDisconnectStops() {
        let (coordinator, receiver, _) = makeSUT()
        coordinator.startSession()
        receiver.emit(.init(phase: .connected, discoveredServiceCount: 1, connectedServiceName: "iPhone"))

        coordinator.disconnect()

        #expect(coordinator.connectionState == .disconnected)
        #expect(coordinator.connectedDeviceName == nil)
        #expect(receiver.stopCount == 1)
    }

    @Test("a deliberate disconnect does not immediately reconnect")
    func deliberateDisconnectDoesNotReconnect() {
        let (coordinator, receiver, _) = makeSUT()
        coordinator.startSession()
        receiver.emit(.init(phase: .connected, discoveredServiceCount: 1, connectedServiceName: "iPhone"))

        coordinator.disconnect()

        // Any trailing status from the transport must be ignored.
        receiver.emit(.init(phase: .browsing, discoveredServiceCount: 1))
        receiver.emit(.init(phase: .connecting, discoveredServiceCount: 1))

        #expect(coordinator.connectionState == .disconnected)
        #expect(receiver.startCount == 1) // never restarted on its own
    }

    @Test("startSession after a deliberate disconnect re-arms the transport")
    func startAfterDisconnect() {
        let (coordinator, receiver, _) = makeSUT()
        coordinator.startSession()
        coordinator.disconnect()

        coordinator.startSession()
        #expect(receiver.startCount == 2)

        receiver.emit(.init(phase: .connecting, discoveredServiceCount: 1))
        #expect(coordinator.connectionState == .connecting)
    }

    // MARK: - LocationStore feeding

    @Test("decoded packets flow into LocationStore, not into the coordinator")
    func packetsFlowToStore() {
        let (coordinator, receiver, store) = makeSUT()
        let p = packet(latitude: 7)

        withExtendedLifetime(coordinator) {
            receiver.emit(p)
            #expect(store.latestPacket == p)
            #expect(store.signal == .live)
        }
    }

    @Test("deliberate disconnect resets the LocationStore signal")
    func disconnectResetsStoreSignal() {
        let (coordinator, receiver, store) = makeSUT()
        coordinator.startSession()
        receiver.emit(packet())
        #expect(store.signal == .live)

        coordinator.disconnect()
        #expect(store.signal == .waiting)
    }

    // MARK: - Pure mapping

    @Test("phase → connection state mapping")
    func phaseMapping() {
        #expect(ConnectionCoordinator.connectionState(for: .stopped) == .disconnected)
        #expect(ConnectionCoordinator.connectionState(for: .browsing) == .discovering)
        #expect(ConnectionCoordinator.connectionState(for: .connecting) == .connecting)
        #expect(ConnectionCoordinator.connectionState(for: .connected) == .connected)
    }

    // MARK: - Separation from pairing state

    @Test("known-device state is independent of connection state")
    func pairingIsSeparateFromConnection() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let known = KnownDeviceStore(defaults: defaults)
        let (coordinator, receiver, _) = makeSUT()

        // Remembering a device does not change connection state.
        known.remember(KnownRelay(bonjourServiceName: "iPhone", displayName: "iPhone"))
        #expect(coordinator.connectionState == .disconnected)

        // Connecting does not add a known device — pairing is a separate flow.
        coordinator.startSession()
        receiver.emit(.init(phase: .connected, discoveredServiceCount: 1, connectedServiceName: "iPhone"))
        #expect(coordinator.connectionState == .connected)
        #expect(known.knownDevices.count == 1) // unchanged

        // Forgetting the device does not touch the live connection.
        known.forgetAll()
        #expect(known.knownDevices.isEmpty)
        #expect(coordinator.connectionState == .connected)
    }
}
