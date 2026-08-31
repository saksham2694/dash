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

    /// One `LocationPacket` as compact JSON followed by a single `\n`.
    public static func encodeLine(
        _ packet: LocationPacket,
        using encoder: JSONEncoder = LocationWireFormat.makeEncoder()
    ) throws -> Data {
        var data = try encoder.encode(packet)
        data.append(lineDelimiter)
        return data
    }
}
