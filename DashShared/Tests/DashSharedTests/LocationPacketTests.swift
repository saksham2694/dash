import Foundation
import Testing
@testable import DashShared

@Suite("LocationPacket JSON round-trip")
struct LocationPacketTests {

    private func makeCoder() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        // Pin the date strategy on both sides so sender and receiver agree.
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }

    @Test("encode then decode yields an equal value")
    func roundTrip() throws {
        let (encoder, decoder) = makeCoder()
        let original = LocationPacket(
            latitude: 12.9716,
            longitude: 77.5946,
            speed: 13.4,
            heading: 92.5,
            timestamp: Date(timeIntervalSince1970: 1_756_700_000)
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(LocationPacket.self, from: data)

        #expect(decoded == original)
    }

    @Test("negative speed and heading survive the round-trip")
    func roundTripInvalidFix() throws {
        let (encoder, decoder) = makeCoder()
        let original = LocationPacket(
            latitude: -33.8688,
            longitude: 151.2093,
            speed: -1,
            heading: -1,
            timestamp: Date(timeIntervalSince1970: 0)
        )

        let decoded = try decoder.decode(
            LocationPacket.self,
            from: try encoder.encode(original)
        )

        #expect(decoded == original)
    }

    @Test("decodes a known JSON payload")
    func decodesKnownPayload() throws {
        let (_, decoder) = makeCoder()
        let json = """
        {
          "latitude": 12.9716,
          "longitude": 77.5946,
          "speed": 13.4,
          "heading": 92.5,
          "timestamp": "2025-09-01T04:13:20Z"
        }
        """.data(using: .utf8)!

        let packet = try decoder.decode(LocationPacket.self, from: json)

        #expect(packet.latitude == 12.9716)
        #expect(packet.longitude == 77.5946)
        #expect(packet.speed == 13.4)
        #expect(packet.heading == 92.5)
        #expect(packet.timestamp == Date(timeIntervalSince1970: 1_756_700_000))
    }

    @Test("JSON contains exactly the five expected keys")
    func encodesExpectedKeys() throws {
        let (encoder, _) = makeCoder()
        let packet = LocationPacket(
            latitude: 1, longitude: 2, speed: 3, heading: 4,
            timestamp: Date(timeIntervalSince1970: 100)
        )

        let object = try JSONSerialization.jsonObject(
            with: try encoder.encode(packet)
        ) as? [String: Any]

        #expect(object?.keys.sorted() == ["heading", "latitude", "longitude", "speed", "timestamp"])
    }
}
