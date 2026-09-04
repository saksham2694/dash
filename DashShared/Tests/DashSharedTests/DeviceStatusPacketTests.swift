import Foundation
import Testing
@testable import DashShared

@Suite("DeviceStatusPacket + wire routing")
struct DeviceStatusPacketTests {

    private let ts = Date(timeIntervalSince1970: 1_756_700_000)

    @Test("encode / decode round-trips every field")
    func roundTrip() throws {
        let original = DeviceStatusPacket(batteryLevel: 0.87, batteryState: .charging, timestamp: ts)
        let data = try LocationWireFormat.makeEncoder().encode(original)
        let decoded = try LocationWireFormat.makeDecoder().decode(DeviceStatusPacket.self, from: data)
        #expect(decoded == original)
        #expect(decoded.kind == DeviceStatusPacket.messageKind)
    }

    @Test("battery level is normalised: negative / non-finite → nil, > 1 → 1")
    func normalisation() {
        #expect(DeviceStatusPacket(batteryLevel: -1, batteryState: .unknown, timestamp: ts).batteryLevel == nil)
        #expect(DeviceStatusPacket(batteryLevel: nil, batteryState: .unknown, timestamp: ts).batteryLevel == nil)
        #expect(DeviceStatusPacket(batteryLevel: 1.5, batteryState: .full, timestamp: ts).batteryLevel == 1)
        #expect(DeviceStatusPacket(batteryLevel: 0.5, batteryState: .unplugged, timestamp: ts).batteryLevel == 0.5)
    }

    @Test("batteryPercent is the rounded whole percentage, or nil")
    func percent() {
        #expect(DeviceStatusPacket(batteryLevel: 0.874, batteryState: .unplugged, timestamp: ts).batteryPercent == 87)
        #expect(DeviceStatusPacket(batteryLevel: 0.876, batteryState: .unplugged, timestamp: ts).batteryPercent == 88)
        #expect(DeviceStatusPacket(batteryLevel: nil, batteryState: .unknown, timestamp: ts).batteryPercent == nil)
    }

    @Test("BatteryState.isPluggedIn is true only for charging and full")
    func pluggedIn() {
        #expect(BatteryState.charging.isPluggedIn)
        #expect(BatteryState.full.isPluggedIn)
        #expect(!BatteryState.unplugged.isPluggedIn)
        #expect(!BatteryState.unknown.isPluggedIn)
    }

    // MARK: - decodeMessage routing (both line kinds on one stream)

    @Test("a device-status line decodes to .deviceStatus")
    func routesDeviceStatus() throws {
        let status = DeviceStatusPacket(batteryLevel: 0.5, batteryState: .charging, timestamp: ts)
        let framed = try LocationWireFormat.encodeLine(status)
        let line = framed.dropLast()   // strip the trailing \n
        #expect(LocationWireFormat.decodeMessage(from: Data(line)) == .deviceStatus(status))
    }

    @Test("a location line still decodes to .location")
    func routesLocation() throws {
        let packet = LocationPacket(latitude: 12.9, longitude: 77.5, speed: 10, heading: 90, timestamp: ts)
        let framed = try LocationWireFormat.encodeLine(packet)
        let line = framed.dropLast()
        #expect(LocationWireFormat.decodeMessage(from: Data(line)) == .location(packet))
    }

    @Test("the two line kinds never decode as each other")
    func disjoint() throws {
        let packet = LocationPacket(latitude: 1, longitude: 2, speed: 3, heading: 4, timestamp: ts)
        let status = DeviceStatusPacket(batteryLevel: 0.4, batteryState: .full, timestamp: ts)

        let packetJSON = try LocationWireFormat.makeEncoder().encode(packet)
        let statusJSON = try LocationWireFormat.makeEncoder().encode(status)

        #expect((try? LocationWireFormat.makeDecoder().decode(DeviceStatusPacket.self, from: packetJSON)) == nil)
        #expect((try? LocationWireFormat.makeDecoder().decode(LocationPacket.self, from: statusJSON)) == nil)

        #expect(LocationWireFormat.decodeMessage(from: packetJSON)?.location == packet)
        #expect(LocationWireFormat.decodeMessage(from: statusJSON)?.deviceStatus == status)
    }

    @Test("a blank / garbage line decodes to nil")
    func garbage() {
        #expect(LocationWireFormat.decodeMessage(from: Data()) == nil)
        #expect(LocationWireFormat.decodeMessage(from: Data("{}".utf8)) == nil)
    }
}
