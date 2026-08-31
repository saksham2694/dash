//
//  LocationBroadcasterTests.swift
//  DashRelayTests
//
//  Covers the networking-independent logic in LocationBroadcaster: the
//  newline-delimited JSON wire framing and the agreed Bonjour service type.
//

import Foundation
import Testing
@testable import DashRelay
import DashShared

@Suite("LocationBroadcaster wire framing")
struct LocationBroadcasterTests {

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

    @Test("advertises the service type both apps agree on")
    func serviceType() {
        #expect(LocationBroadcaster.serviceType == "_dashrelay._tcp")
    }

    @Test("a line is compact JSON terminated by exactly one newline")
    func lineShape() throws {
        let data = try LocationBroadcaster.encodeLine(packet())

        #expect(data.last == 0x0A)
        // No interior newlines — the delimiter must be unambiguous.
        #expect(data.dropLast().contains(0x0A) == false)
    }

    @Test("a line decodes back to an equal packet")
    func lineRoundTrips() throws {
        let original = packet()
        let data = try LocationBroadcaster.encodeLine(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LocationPacket.self, from: data.dropLast())

        #expect(decoded == original)
    }

    @Test("consecutive lines split on newline into the original packets")
    func streamOfLinesIsSplittable() throws {
        let first = packet(latitude: 1, longitude: 2)
        let second = packet(latitude: 3, longitude: 4, speed: -1, heading: -1)

        var stream = Data()
        stream.append(try LocationBroadcaster.encodeLine(first))
        stream.append(try LocationBroadcaster.encodeLine(second))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = stream
            .split(separator: 0x0A, omittingEmptySubsequences: true)
            .map { try! decoder.decode(LocationPacket.self, from: Data($0)) }

        #expect(decoded == [first, second])
    }

    @Test("broadcast and stop before start are safe no-ops")
    func lifecycleGuards() {
        let broadcaster = LocationBroadcaster()
        broadcaster.broadcast(packet())
        broadcaster.stop()
    }
}
