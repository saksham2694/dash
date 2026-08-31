//
//  PacketLineBufferTests.swift
//  DashTests
//
//  Covers the receive-side framing/decoding: reassembling a byte stream into
//  LocationPackets. No networking — testable without a second device.
//

import Foundation
import Testing
@testable import Dash
import DashShared

@Suite("PacketLineBuffer")
struct PacketLineBufferTests {

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

    /// Encode exactly the way the relay puts bytes on the wire.
    private func line(_ packet: LocationPacket) throws -> Data {
        try LocationWireFormat.encodeLine(packet)
    }

    @Test("decodes one complete line")
    func singleLine() throws {
        var buffer = PacketLineBuffer()
        let expected = packet()

        let out = buffer.append(try line(expected))

        #expect(out == [expected])
    }

    @Test("decodes two lines delivered in one chunk")
    func twoLinesOneChunk() throws {
        var buffer = PacketLineBuffer()
        let a = packet(latitude: 1, longitude: 2)
        let b = packet(latitude: 3, longitude: 4)

        var chunk = Data()
        chunk.append(try line(a))
        chunk.append(try line(b))

        #expect(buffer.append(chunk) == [a, b])
    }

    @Test("reassembles a line split across chunks")
    func lineSplitAcrossChunks() throws {
        var buffer = PacketLineBuffer()
        let expected = packet()
        let full = try line(expected)
        let cut = full.count / 2

        #expect(buffer.append(full.prefix(cut)).isEmpty)
        #expect(buffer.append(full.suffix(from: full.startIndex + cut)) == [expected])
    }

    @Test("holds a partial trailing line until its newline arrives")
    func partialTrailingLine() throws {
        var buffer = PacketLineBuffer()
        let a = packet(latitude: 1)
        let b = packet(latitude: 2)

        var chunk = try line(a)
        let bLine = try line(b)
        chunk.append(bLine.dropLast(5)) // b without its newline (and a few bytes)

        #expect(buffer.append(chunk) == [a])
        #expect(buffer.append(bLine.suffix(5)) == [b])
    }

    @Test("ignores blank lines")
    func blankLinesIgnored() throws {
        var buffer = PacketLineBuffer()
        let expected = packet()

        var chunk = Data([0x0A, 0x0A]) // two empty lines
        chunk.append(try line(expected))
        chunk.append(0x0A)

        #expect(buffer.append(chunk) == [expected])
    }

    @Test("skips a malformed line but keeps decoding the rest")
    func malformedLineSkipped() throws {
        var buffer = PacketLineBuffer()
        let good = packet()

        var chunk = Data("{not valid json}\n".utf8)
        chunk.append(try line(good))

        #expect(buffer.append(chunk) == [good])
    }

    @Test("recovers after an oversized un-terminated line is dropped")
    func oversizedLineDropped() throws {
        var buffer = PacketLineBuffer()
        let garbage = Data(repeating: 0x41, count: PacketLineBuffer.maxLineBytes + 1) // no newline

        #expect(buffer.append(garbage).isEmpty)

        let expected = packet()
        #expect(buffer.append(try line(expected)) == [expected])
    }

    @Test("reset() discards a buffered partial line")
    func resetClearsPartial() throws {
        var buffer = PacketLineBuffer()
        let dropped = packet(latitude: 9)
        buffer.append(try line(dropped).dropLast()) // partial, no newline

        buffer.reset()

        let expected = packet(latitude: 1)
        #expect(buffer.append(try line(expected)) == [expected])
    }

    @Test("round-trips shared wire-format output back to the original packet")
    func matchesSharedWireFormat() throws {
        var buffer = PacketLineBuffer()
        let original = packet(speed: -1, heading: -1) // invalid-fix sentinels survive too

        #expect(buffer.append(try LocationWireFormat.encodeLine(original)) == [original])
    }
}
