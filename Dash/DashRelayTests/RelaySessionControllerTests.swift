//
//  RelaySessionControllerTests.swift
//  DashRelayTests
//
//  The iPhone session state machine, driven through stub tracker/broadcaster —
//  no CLLocationManager, no NWListener.
//

import Foundation
import Testing
@testable import DashRelay
import DashShared

@MainActor
final class StubRelayTracker: RelayTracking {
    var onPacket: ((LocationPacket) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

final class StubRelayBroadcaster: RelayBroadcasting, @unchecked Sendable {
    var onStatusChange: (@MainActor @Sendable (LocationBroadcaster.Status) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var broadcastCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func broadcast(_ packet: LocationPacket) { broadcastCount += 1 }

    @MainActor func emit(_ status: LocationBroadcaster.Status) { onStatusChange?(status) }
}

@MainActor
@Suite("RelaySessionController")
struct RelaySessionControllerTests {

    private func makeSUT() -> (RelaySessionController, StubRelayTracker, StubRelayBroadcaster) {
        let tracker = StubRelayTracker()
        let broadcaster = StubRelayBroadcaster()
        let controller = RelaySessionController(tracker: tracker, broadcaster: broadcaster)
        return (controller, tracker, broadcaster)
    }

    private var packet: LocationPacket {
        LocationPacket(latitude: 1, longitude: 2, speed: 0, heading: -1,
                       timestamp: Date(timeIntervalSince1970: 1_756_700_000))
    }

    // MARK: - Transitions

    @Test("starts stopped")
    func initialState() {
        let (controller, _, _) = makeSUT()
        #expect(controller.state == .stopped)
        #expect(controller.isTrackingLocation == false)
    }

    @Test("start → waiting, and begins advertising + GPS")
    func startEntersWaiting() {
        let (controller, tracker, broadcaster) = makeSUT()

        controller.start()

        #expect(controller.state == .waiting)
        #expect(controller.isTrackingLocation)
        #expect(broadcaster.startCount == 1)
        #expect(tracker.startCount == 1)
    }

    @Test("waiting → connected when a dashboard connects, and back to waiting")
    func clientConnectAndDisconnect() {
        let (controller, _, broadcaster) = makeSUT()
        controller.start()

        broadcaster.emit(.init(isListening: true, clientCount: 1))
        #expect(controller.state == .connected)

        broadcaster.emit(.init(isListening: true, clientCount: 0))
        #expect(controller.state == .waiting)
    }

    @Test("connected → stopped on a deliberate disconnect")
    func stopFromConnected() {
        let (controller, tracker, broadcaster) = makeSUT()
        controller.start()
        broadcaster.emit(.init(isListening: true, clientCount: 1))

        controller.stop()

        #expect(controller.state == .stopped)
        #expect(broadcaster.stopCount == 1)
        #expect(tracker.stopCount == 1)
        #expect(controller.isTrackingLocation == false)
    }

    // MARK: - Deliberate disconnect

    @Test("stopping a relay session stops location tracking")
    func stopStopsTracking() {
        let (controller, tracker, _) = makeSUT()
        controller.start()
        #expect(tracker.startCount == 1)

        controller.stop()

        #expect(tracker.stopCount == 1)
        #expect(controller.isTrackingLocation == false)
    }

    @Test("a deliberate disconnect does not immediately reconnect")
    func deliberateDisconnectDoesNotReconnect() {
        let (controller, tracker, broadcaster) = makeSUT()
        controller.start()
        controller.stop()

        // Trailing / spurious broadcaster status must not revive the session.
        broadcaster.emit(.init(isListening: false, clientCount: 0))
        broadcaster.emit(.init(isListening: true, clientCount: 1))

        #expect(controller.state == .stopped)
        #expect(tracker.startCount == 1)   // never restarted
        #expect(broadcaster.startCount == 1)
    }

    @Test("start after a deliberate stop resumes the session")
    func startAfterStop() {
        let (controller, tracker, broadcaster) = makeSUT()
        controller.start()
        controller.stop()

        controller.start()

        #expect(controller.state == .waiting)
        #expect(tracker.startCount == 2)
        #expect(broadcaster.startCount == 2)
    }

    // MARK: - Packet forwarding

    @Test("GPS fixes are forwarded straight to the broadcaster")
    func fixesForwarded() {
        let (_, tracker, broadcaster) = makeSUT()
        tracker.onPacket?(packet)
        #expect(broadcaster.broadcastCount == 1)
    }
}
