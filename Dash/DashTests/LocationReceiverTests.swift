//
//  LocationReceiverTests.swift
//  DashTests
//
//  Non-networking checks for LocationReceiver: the agreed service type, the
//  JSON/date strategy that must match LocationBroadcaster, and the pure
//  Bonjour-metadata → RelayAdvertisement mapping used during discovery.
//

import Foundation
import Network
import Testing
@testable import Dash
import DashShared

@Suite("LocationReceiver")
struct LocationReceiverTests {

    @Test("browses the same service type the shared wire format defines")
    func serviceTypeMatchesWireFormat() {
        #expect(LocationReceiver.serviceType == "_dashrelay._tcp")
        #expect(LocationReceiver.serviceType == LocationWireFormat.bonjourServiceType)
    }

    // MARK: - Discovery: browse metadata → RelayAdvertisement

    /// End-to-end of the discovery parse: `NWBrowser.Result.Metadata` →
    /// `LocationReceiver.txtEntries(from:)` → `RelayAdvertisement(txtRecordEntries:)`
    /// — the same path `handleBrowseResults` runs.
    private func advertisement(for metadata: NWBrowser.Result.Metadata) -> RelayAdvertisement? {
        guard let entries = LocationReceiver.txtEntries(from: metadata) else { return nil }
        return RelayAdvertisement(txtRecordEntries: entries)
    }

    @Test("resolved Bonjour TXT metadata parses into a RelayAdvertisement")
    func resolvedTXTMetadataParses() {
        let txt = NWTXTRecord([
            RelayAdvertisement.idKey: "E1496E5F-CEC6-4595-90C0-9FDAC873B152",
            RelayAdvertisement.displayNameKey: "Saksham’s iPhone",
        ])

        let entries = LocationReceiver.txtEntries(from: .bonjour(txt))
        #expect(entries?[RelayAdvertisement.idKey] == "E1496E5F-CEC6-4595-90C0-9FDAC873B152")

        let ad = advertisement(for: .bonjour(txt))
        #expect(ad?.id == "E1496E5F-CEC6-4595-90C0-9FDAC873B152")
        #expect(ad?.displayName == "Saksham’s iPhone")
    }

    @Test("nil metadata yields no TXT entries and no advertisement (not resolved yet)")
    func nilMetadataYieldsNothing() {
        // The exact physical-device failure mode: NWBrowser delivers the service
        // endpoint but `metadata == .none`. The relay must be skipped, not
        // surfaced with a bogus identity — a later result carries the TXT.
        #expect(LocationReceiver.txtEntries(from: .none) == nil)
        #expect(advertisement(for: .none) == nil)
    }

    @Test("TXT metadata without a stable rid yields no advertisement")
    func txtWithoutRidYieldsNoAdvertisement() {
        let noRid = NWTXTRecord([RelayAdvertisement.displayNameKey: "iPhone"])
        #expect(advertisement(for: .bonjour(noRid)) == nil)

        let emptyRid = NWTXTRecord([
            RelayAdvertisement.idKey: "",
            RelayAdvertisement.displayNameKey: "iPhone",
        ])
        #expect(advertisement(for: .bonjour(emptyRid)) == nil)
    }

    @Test("TXT metadata with rid but no name parses with an empty display name")
    func txtWithRidOnlyParses() {
        let ridOnly = NWTXTRecord([RelayAdvertisement.idKey: "ABC-123"])
        let ad = advertisement(for: .bonjour(ridOnly))
        #expect(ad?.id == "ABC-123")
        #expect(ad?.displayName == "")
    }

    @Test("decoder uses the same ISO-8601 date strategy as the encoder")
    func decoderMatchesEncoder() throws {
        let original = LocationPacket(
            latitude: 12.9716, longitude: 77.5946,
            speed: 13.4, heading: 92.5,
            timestamp: Date(timeIntervalSince1970: 1_756_700_000)
        )

        let wire = try LocationWireFormat.encodeLine(original).dropLast() // strip "\n"
        let decoded = try LocationReceiver.makeDecoder().decode(LocationPacket.self, from: Data(wire))

        #expect(decoded == original)
    }

    @Test("stop before start is a safe no-op")
    func stopBeforeStartIsSafe() {
        let receiver = LocationReceiver()
        receiver.stop()
    }
}
