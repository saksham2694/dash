//
//  LocationStoreTests.swift
//  DashTests
//
//  Store + watchdog behaviour, driven by synthetic packets and injected times —
//  no real networking.
//

import Foundation
import Testing
@testable import Dash
import DashShared

@MainActor
@Suite("LocationStore")
struct LocationStoreTests {

    private func packet(
        latitude: Double = 12.9716,
        longitude: Double = 77.5946,
        speed: Double = 13.4,
        heading: Double = 92.5,
        timestamp: Date = Date(timeIntervalSince1970: 1_756_700_000)
    ) -> LocationPacket {
        LocationPacket(
            latitude: latitude, longitude: longitude,
            speed: speed, heading: heading, timestamp: timestamp
        )
    }

    // MARK: - Initial state

    @Test("starts empty and waiting")
    func initialState() {
        let store = LocationStore()
        #expect(store.latestPacket == nil)
        #expect(store.signal == .waiting)
        #expect(store.linkPhase == .stopped)
        #expect(store.hasFix == false)
        #expect(store.isSignalLost == false)
    }

    // MARK: - Ingestion

    @Test("ingest becomes the source of truth and goes live")
    func ingestUpdatesState() {
        let store = LocationStore()
        let p = packet()

        store.ingest(p)

        #expect(store.latestPacket == p)
        #expect(store.signal == .live)
        #expect(store.hasFix)
        #expect(store.speed == p.speed)
        #expect(store.heading == p.heading)
    }

    @Test("latestPacket is always the most recent")
    func latestWins() {
        let store = LocationStore()
        store.ingest(packet(latitude: 1))
        store.ingest(packet(latitude: 2))
        store.ingest(packet(latitude: 3))
        #expect(store.latestPacket?.latitude == 3)
    }

    // MARK: - Watchdog

    @Test("stays live while packets are within the stale interval")
    func liveWithinInterval() {
        let store = LocationStore(staleInterval: 8)
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        store.ingest(packet(), at: t0)
        store.refreshSignal(now: t0.addingTimeInterval(5))

        #expect(store.signal == .live)
    }

    @Test("goes stale once the interval elapses without a packet")
    func goesStale() {
        let store = LocationStore(staleInterval: 8)
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        store.ingest(packet(), at: t0)
        store.refreshSignal(now: t0.addingTimeInterval(8))

        #expect(store.signal == .stale)
        #expect(store.isSignalLost)
    }

    @Test("keeps last-known packet when the signal is lost")
    func staleRetainsPacket() {
        let store = LocationStore(staleInterval: 5)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let p = packet(latitude: 42)

        store.ingest(p, at: t0)
        store.refreshSignal(now: t0.addingTimeInterval(10))

        #expect(store.signal == .stale)
        #expect(store.latestPacket == p)
    }

    @Test("a fresh packet recovers from stale to live")
    func recoversAfterStale() {
        let store = LocationStore(staleInterval: 5)
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        store.ingest(packet(), at: t0)
        store.refreshSignal(now: t0.addingTimeInterval(10))
        #expect(store.signal == .stale)

        store.ingest(packet(), at: t0.addingTimeInterval(11))
        #expect(store.signal == .live)
    }

    @Test("watchdog task flips the signal on its own")
    func watchdogFiresAutomatically() async throws {
        let store = LocationStore(staleInterval: 0.1)
        store.ingest(packet())
        #expect(store.signal == .live)

        try await Task.sleep(for: .seconds(0.3))

        #expect(store.signal == .stale)
    }

    // MARK: - Link phase / connection state

    @Test("connects to the receiver's packet callback")
    func wiredToReceiver() {
        let receiver = LocationReceiver()
        let store = LocationStore(receiver: receiver)
        let p = packet(latitude: 7)

        receiver.onPacket?(p) // simulate a decoded packet from the network layer

        #expect(store.latestPacket == p)
        #expect(store.signal == .live)
    }

    @Test("mirrors the receiver's link phase")
    func mirrorsLinkPhase() {
        let receiver = LocationReceiver()
        let store = LocationStore(receiver: receiver)

        receiver.onStatusChange?(.init(phase: .connecting, discoveredServiceCount: 1))
        #expect(store.linkPhase == .connecting)

        receiver.onStatusChange?(.init(phase: .connected, discoveredServiceCount: 1))
        #expect(store.linkPhase == .connected)
    }

    @Test("a brief link drop does not immediately blank the signal")
    func linkDropKeepsLastKnown() {
        let receiver = LocationReceiver()
        let store = LocationStore(receiver: receiver)
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        store.ingest(packet(), at: t0)
        receiver.onStatusChange?(.init(phase: .browsing, discoveredServiceCount: 0))

        #expect(store.linkPhase == .browsing)
        #expect(store.signal == .live)
        #expect(store.latestPacket != nil)
    }

    @Test("stop resets the signal to waiting but keeps last-known packet")
    func stopResets() {
        let store = LocationStore()
        let p = packet()
        store.ingest(p)

        store.stop()

        #expect(store.signal == .waiting)
        #expect(store.latestPacket == p)
    }
}
