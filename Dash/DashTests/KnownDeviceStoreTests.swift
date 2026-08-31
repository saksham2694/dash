//
//  KnownDeviceStoreTests.swift
//  DashTests
//
//  Pairing / known-device persistence. Isolated `UserDefaults` per test; no
//  connection layer involved (that separation is asserted here and in
//  ConnectionCoordinatorTests).
//

import Foundation
import Testing
@testable import Dash

@MainActor
@Suite("KnownDeviceStore")
struct KnownDeviceStoreTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "knowndevices-test-\(UUID().uuidString)")!
    }

    private func device(_ name: String) -> KnownRelay {
        KnownRelay(bonjourServiceName: name, displayName: name)
    }

    @Test("starts empty")
    func startsEmpty() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        #expect(store.knownDevices.isEmpty)
    }

    @Test("remember adds a device")
    func rememberAdds() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        store.remember(device("iPhone"))
        #expect(store.knownDevices.map(\.id) == ["iPhone"])
        #expect(store.isKnown(bonjourServiceName: "iPhone"))
    }

    @Test("remember is idempotent by id")
    func rememberIdempotent() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        store.remember(device("iPhone"))
        store.remember(KnownRelay(bonjourServiceName: "iPhone", displayName: "Renamed"))
        #expect(store.knownDevices.count == 1)
        #expect(store.knownDevices.first?.displayName == "Renamed")
    }

    @Test("forget removes a device")
    func forgetRemoves() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        let d = device("iPhone")
        store.remember(d)
        store.forget(d)
        #expect(store.knownDevices.isEmpty)
        #expect(store.isKnown(bonjourServiceName: "iPhone") == false)
    }

    @Test("supports multiple known devices")
    func multipleDevices() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        store.remember(device("iPhone A"))
        store.remember(device("iPhone B"))
        #expect(Set(store.knownDevices.map(\.id)) == ["iPhone A", "iPhone B"])

        store.forget(device("iPhone A"))
        #expect(store.knownDevices.map(\.id) == ["iPhone B"])
    }

    @Test("forgetAll clears everything")
    func forgetAllClears() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        store.remember(device("A"))
        store.remember(device("B"))
        store.forgetAll()
        #expect(store.knownDevices.isEmpty)
    }

    @Test("known devices persist across store instances")
    func persistsAcrossInstances() {
        let defaults = makeDefaults()

        let first = KnownDeviceStore(defaults: defaults)
        first.remember(device("iPhone"))

        let second = KnownDeviceStore(defaults: defaults)
        #expect(second.knownDevices.map(\.id) == ["iPhone"])
    }
}
