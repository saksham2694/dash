//
//  LocationReceiverTests.swift
//  DashTests
//
//  Non-networking checks for LocationReceiver: the agreed service type and the
//  JSON/date strategy that must match LocationBroadcaster.
//

import Foundation
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
