//
//  PacketLineBuffer.swift
//  Dash
//
//  Reassembles a byte stream into `LocationPacket` values. The relay sends each
//  packet as compact JSON followed by a single `\n`; TCP does not preserve those
//  boundaries, so incoming chunks are buffered and split on `\n` here.
//
//  Pure value type, no networking — this is the part that can be tested without
//  two devices.
//

import DashShared
import Foundation

struct PacketLineBuffer {

    /// Hard cap on an un-terminated line. A stream that blows past this without a
    /// newline is treated as corrupt and dropped, so a bad peer can't grow the
    /// buffer without bound.
    static let maxLineBytes = 64 * 1024

    private static let newline = LocationWireFormat.lineDelimiter

    private var buffer = Data()
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = LocationReceiver.makeDecoder()) {
        self.decoder = decoder
    }

    /// Append freshly received bytes and return every packet that just became
    /// complete. Blank lines are ignored; a line that fails to decode is skipped
    /// without disturbing the rest of the stream.
    mutating func append(_ data: Data) -> [LocationPacket] {
        buffer.append(data)

        var packets: [LocationPacket] = []
        while let newlineIndex = buffer.firstIndex(of: Self.newline) {
            let line = buffer[buffer.startIndex..<newlineIndex]
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            guard !line.isEmpty else { continue }
            if let packet = try? decoder.decode(LocationPacket.self, from: Data(line)) {
                packets.append(packet)
            }
        }

        if buffer.count > Self.maxLineBytes {
            buffer.removeAll(keepingCapacity: false)
        }
        return packets
    }

    /// Discard any partial line — call this on (re)connect.
    mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}
