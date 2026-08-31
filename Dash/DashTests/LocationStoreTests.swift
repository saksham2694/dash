//
//  LocationStoreTests.swift
//  DashTests
//
//  Store + watchdog behaviour, driven by synthetic packets and injected times —
//  no real networking. Connection-state wiring lives in ConnectionCoordinatorTests.
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

    // MARK: - Session end

    @Test("connectionEnded returns to waiting but keeps last-known packet")
    func connectionEndedResets() {
        let store = LocationStore()
        let p = packet()
        store.ingest(p)

        store.connectionEnded()

        #expect(store.signal == .waiting)
        #expect(store.latestPacket == p)
    }

    @Test("connectionEnded keeps the signal at waiting even past the interval")
    func connectionEndedStaysWaiting() {
        let store = LocationStore(staleInterval: 5)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.ingest(packet(), at: t0)

        store.connectionEnded()
        store.refreshSignal(now: t0.addingTimeInterval(60))

        #expect(store.signal == .waiting) // not .stale — we're not trying anymore
    }
}
