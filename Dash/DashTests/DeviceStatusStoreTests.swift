//
//  DeviceStatusStoreTests.swift
//  DashTests
//
//  `DeviceStatusStore` (M5.7) — the iPad's source of truth for iPhone battery
//  telemetry: ingest, freshness transitions, disconnect handling, and the
//  long-grace watchdog.
//

import Foundation
import Testing
import DashShared
@testable import Dash

@MainActor
@Suite("DeviceStatusStore")
struct DeviceStatusStoreTests {

    private let t0 = Date(timeIntervalSince1970: 1_756_700_000)

    private func status(_ level: Double?, _ state: BatteryState, at date: Date) -> DeviceStatusPacket {
        DeviceStatusPacket(batteryLevel: level, batteryState: state, timestamp: date)
    }

    @Test("starts unavailable with no reading")
    func initialState() {
        let store = DeviceStatusStore()
        #expect(store.batteryLevel == nil)
        #expect(store.batteryState == .unknown)
        #expect(store.freshness == .unavailable)
        #expect(store.hasReading == false)
    }

    @Test("ingest records level + state and goes live")
    func ingestUpdates() {
        let store = DeviceStatusStore()
        store.ingest(status(0.87, .unplugged, at: t0), at: t0)

        #expect(store.batteryLevel == 0.87)
        #expect(store.batteryPercent == 87)
        #expect(store.batteryState == .unplugged)
        #expect(store.freshness == .live)
        #expect(store.hasReading)
    }

    @Test("an unknown battery level ingests as nil")
    func unknownLevel() {
        let store = DeviceStatusStore()
        store.ingest(status(nil, .unknown, at: t0), at: t0)
        #expect(store.batteryLevel == nil)
        #expect(store.batteryPercent == nil)
        // freshness is still .live — we did receive a packet, it just had no level.
        #expect(store.freshness == .live)
    }

    @Test("a later packet replaces the earlier one")
    func replacesEarlier() {
        let store = DeviceStatusStore()
        store.ingest(status(0.50, .unplugged, at: t0), at: t0)
        store.ingest(status(0.55, .charging, at: t0.addingTimeInterval(60)), at: t0.addingTimeInterval(60))
        #expect(store.batteryPercent == 55)
        #expect(store.batteryState == .charging)
    }

    @Test("connectionEnded keeps the last value but marks it stale")
    func connectionEndedStale() {
        let store = DeviceStatusStore()
        store.ingest(status(0.42, .unplugged, at: t0), at: t0)
        store.connectionEnded()

        #expect(store.batteryPercent == 42)      // kept for display
        #expect(store.freshness == .stale)
        #expect(store.hasReading)                // still a (stale) reading
    }

    @Test("connectionEnded with no reading stays unavailable")
    func connectionEndedUnavailable() {
        let store = DeviceStatusStore()
        store.connectionEnded()
        #expect(store.freshness == .unavailable)
        #expect(store.hasReading == false)
    }

    @Test("the watchdog marks a long-quiet reading stale while still connected")
    func watchdogStale() {
        let store = DeviceStatusStore(graceInterval: 180)
        store.ingest(status(0.90, .unplugged, at: t0), at: t0)

        store.refreshFreshness(now: t0.addingTimeInterval(120))
        #expect(store.freshness == .live)

        store.refreshFreshness(now: t0.addingTimeInterval(200))
        #expect(store.freshness == .stale)
    }

    @Test("a fresh packet after staleness returns to live")
    func recoversFromStale() {
        let store = DeviceStatusStore(graceInterval: 180)
        store.ingest(status(0.30, .unplugged, at: t0), at: t0)
        store.refreshFreshness(now: t0.addingTimeInterval(300))
        #expect(store.freshness == .stale)

        store.ingest(status(0.29, .unplugged, at: t0.addingTimeInterval(310)), at: t0.addingTimeInterval(310))
        #expect(store.freshness == .live)
    }
}
