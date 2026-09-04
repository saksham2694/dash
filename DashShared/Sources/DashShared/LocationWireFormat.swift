import Foundation

/// The contract for the DashRelay → Dash location link: the Bonjour service type
/// and the exact JSON/date strategy and line framing used on the wire.
///
/// Both apps go through this type so the sender and receiver can never silently
/// drift apart — the same reason `LocationPacket` lives here.
public enum LocationWireFormat {

    /// The Bonjour service type the iPhone advertises and the iPad browses for.
    public static let bonjourServiceType = "_dashrelay._tcp"

    /// A `JSONEncoder` configured for the wire format.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// A `JSONDecoder` that matches `makeEncoder()`.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// A single newline character (`\n`) — the delimiter between packets.
    public static let lineDelimiter: UInt8 = 0x0A

    /// One `LocationPacket` as compact JSON followed by a single `\n`. The wire
    /// bytes are unchanged from before device-status telemetry existed.
    public static func encodeLine(
        _ packet: LocationPacket,
        using encoder: JSONEncoder = LocationWireFormat.makeEncoder()
    ) throws -> Data {
        try encodeLine(value: packet, using: encoder)
    }

    /// One `DeviceStatusPacket` as compact JSON followed by a single `\n` — the
    /// second line kind on the same stream.
    public static func encodeLine(
        _ status: DeviceStatusPacket,
        using encoder: JSONEncoder = LocationWireFormat.makeEncoder()
    ) throws -> Data {
        try encodeLine(value: status, using: encoder)
    }

    /// Shared framing: compact JSON for `value` + one `\n`.
    private static func encodeLine(
        value: some Encodable,
        using encoder: JSONEncoder
    ) throws -> Data {
        var data = try encoder.encode(value)
        data.append(lineDelimiter)
        return data
    }

    /// Decode one already-de-framed line into a `RelayMessage`. A device-status
    /// line (it carries `kind`) is tried first; otherwise a `LocationPacket`.
    /// `nil` for a blank / undecodable line.
    public static func decodeMessage(
        from line: Data,
        using decoder: JSONDecoder = LocationWireFormat.makeDecoder()
    ) -> RelayMessage? {
        if let status = try? decoder.decode(DeviceStatusPacket.self, from: line),
           status.kind == DeviceStatusPacket.messageKind {
            return .deviceStatus(status)
        }
        if let packet = try? decoder.decode(LocationPacket.self, from: line) {
            return .location(packet)
        }
        return nil
    }
}
