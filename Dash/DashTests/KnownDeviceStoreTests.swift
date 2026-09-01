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

    private func device(_ id: String, name: String? = nil) -> KnownRelay {
        KnownRelay(id: id, displayName: name ?? id)
    }

    @Test("starts empty")
    func startsEmpty() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        #expect(store.knownDevices.isEmpty)
        #expect(store.pairedRelay == nil)
    }

    @Test("remember adds a device and it becomes the paired relay")
    func rememberAdds() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        store.remember(device("relay-1", name: "iPhone"))
        #expect(store.knownDevices.map(\.id) == ["relay-1"])
        #expect(store.isKnown(id: "relay-1"))
        #expect(store.pairedRelay?.id == "relay-1")
    }

    @Test("remember is idempotent by id and refreshes the display name")
    func rememberIdempotent() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        store.remember(device("relay-1", name: "iPhone"))
        store.remember(device("relay-1", name: "Renamed iPhone"))
        #expect(store.knownDevices.count == 1)
        #expect(store.knownDevices.first?.displayName == "Renamed iPhone")
    }

    @Test("forget removes a device")
    func forgetRemoves() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        let d = device("relay-1")
        store.remember(d)
        store.forget(d)
        #expect(store.knownDevices.isEmpty)
        #expect(store.isKnown(id: "relay-1") == false)
    }

    @Test("supports multiple known devices")
    func multipleDevices() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        store.remember(device("relay-a"))
        store.remember(device("relay-b"))
        #expect(Set(store.knownDevices.map(\.id)) == ["relay-a", "relay-b"])

        store.forget(device("relay-a"))
        #expect(store.knownDevices.map(\.id) == ["relay-b"])
    }

    @Test("forgetAll clears everything")
    func forgetAllClears() {
        let store = KnownDeviceStore(defaults: makeDefaults())
        store.remember(device("a"))
        store.remember(device("b"))
        store.forgetAll()
        #expect(store.knownDevices.isEmpty)
    }

    @Test("known devices persist across store instances")
    func persistsAcrossInstances() {
        let defaults = makeDefaults()

        let first = KnownDeviceStore(defaults: defaults)
        first.remember(device("relay-1", name: "iPhone"))

        let second = KnownDeviceStore(defaults: defaults)
        #expect(second.knownDevices.map(\.id) == ["relay-1"])
        #expect(second.pairedRelay?.displayName == "iPhone")
    }
}
