//
//  PacketLineBuffer.swift
//  Dash
//
//  Reassembles a byte stream into `RelayMessage` values — a `LocationPacket` or a
//  `DeviceStatusPacket`, on the same stream. The relay sends each as compact JSON
//  followed by a single `\n`; TCP does not preserve those boundaries, so incoming
//  chunks are buffered and split on `\n` here, then each line is decoded via
//  `LocationWireFormat.decodeMessage(from:)`.
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

    /// Append freshly received bytes and return every message that just became
    /// complete, in arrival order. Blank lines are ignored; a line that fails to
    /// decode is skipped without disturbing the rest of the stream.
    mutating func append(_ data: Data) -> [RelayMessage] {
        buffer.append(data)

        var messages: [RelayMessage] = []
        while let newlineIndex = buffer.firstIndex(of: Self.newline) {
            let line = buffer[buffer.startIndex..<newlineIndex]
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            guard !line.isEmpty else { continue }
            if let message = LocationWireFormat.decodeMessage(from: Data(line), using: decoder) {
                messages.append(message)
            }
        }

        if buffer.count > Self.maxLineBytes {
            buffer.removeAll(keepingCapacity: false)
        }
        return messages
    }

    /// Discard any partial line — call this on (re)connect.
    mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}
