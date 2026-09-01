//
//  RelayIdentityTests.swift
//  DashRelayTests
//
//  The relay's stable pairing identity: minted once, persisted, reused.
//

import Foundation
import Testing
@testable import DashRelay
import DashShared

@Suite("RelayIdentity")
struct RelayIdentityTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "relayidentity-test-\(UUID().uuidString)")!
    }

    @Test("mints an id on first use and reuses it afterwards")
    func stableAcrossLoads() {
        let defaults = makeDefaults()

        let first = RelayIdentity.load(defaults: defaults, deviceName: "iPhone")
        let second = RelayIdentity.load(defaults: defaults, deviceName: "iPhone")

        #expect(first.id.isEmpty == false)
        #expect(first.id == second.id)
    }

    @Test("different installs (different stores) get different ids")
    func distinctPerInstall() {
        let a = RelayIdentity.load(defaults: makeDefaults(), deviceName: "iPhone")
        let b = RelayIdentity.load(defaults: makeDefaults(), deviceName: "iPhone")
        #expect(a.id != b.id)
    }

    @Test("carries the device name through as the display name")
    func displayName() {
        let ad = RelayIdentity.load(defaults: makeDefaults(), deviceName: "Saksham's iPhone")
        #expect(ad.displayName == "Saksham's iPhone")
    }

    @Test("a renamed device keeps the same identity")
    func renameKeepsIdentity() {
        let defaults = makeDefaults()
        let before = RelayIdentity.load(defaults: defaults, deviceName: "iPhone")
        let after = RelayIdentity.load(defaults: defaults, deviceName: "New Name")
        #expect(before.id == after.id)
        #expect(after.displayName == "New Name")
    }
}
