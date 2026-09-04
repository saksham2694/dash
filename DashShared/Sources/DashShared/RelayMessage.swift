import Foundation

/// One decoded message from the DashRelay → Dash link. The stream carries two
/// line kinds — a `LocationPacket` (unchanged wire format) and a
/// `DeviceStatusPacket` — and this is what the receiver gets after framing +
/// decoding (`LocationWireFormat.decodeMessage(from:)`). New kinds are added
/// here without disturbing either existing one.
public enum RelayMessage: Equatable, Sendable {
    case location(LocationPacket)
    case deviceStatus(DeviceStatusPacket)

    public var location: LocationPacket? {
        if case .location(let packet) = self { return packet }
        return nil
    }

    public var deviceStatus: DeviceStatusPacket? {
        if case .deviceStatus(let status) = self { return status }
        return nil
    }
}
