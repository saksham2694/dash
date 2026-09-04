import Foundation

/// Device / relay status telemetry relayed from the iPhone companion app
/// (DashRelay) to the iPad dashboard app (Dash) — **separate from** GPS.
///
/// `LocationPacket` stays purely about location; anything about the *device* (the
/// iPhone battery now; relay health / thermal / network fields later) lives here
/// and can grow without touching the location contract. Both apps share this
/// type for the same reason they share `LocationPacket` — the sender and
/// receiver must never drift apart. Platform-independent: no UIKit.
public struct DeviceStatusPacket: Codable, Equatable, Sendable {

    /// Message discriminator. Always `Self.messageKind` — lets the receiver tell
    /// a device-status line apart from a `LocationPacket` line on the same stream.
    public let kind: String

    /// Battery charge in `0...1`, or `nil` when the sending device can't report
    /// it (`UIDevice.batteryLevel < 0` — monitoring off / simulator / unknown).
    public var batteryLevel: Double?

    /// Battery charging state.
    public var batteryState: BatteryState

    /// When this status was produced on the sending device.
    public var timestamp: Date

    /// The value `kind` always carries.
    public static let messageKind = "deviceStatus"

    public init(batteryLevel: Double?, batteryState: BatteryState, timestamp: Date) {
        self.kind = Self.messageKind
        self.batteryLevel = Self.normalise(batteryLevel)
        self.batteryState = batteryState
        self.timestamp = timestamp
    }

    /// Clamp to `0...1`; a negative / non-finite input means "unknown" → `nil`.
    public static func normalise(_ level: Double?) -> Double? {
        guard let level, level.isFinite, level >= 0 else { return nil }
        return min(1, level)
    }

    /// Battery charge as a whole percentage (`0...100`), or `nil` when unknown.
    public var batteryPercent: Int? {
        batteryLevel.map { Int(($0 * 100).rounded()) }
    }
}

/// Platform-independent mirror of `UIDevice.BatteryState`. DashRelay maps the
/// UIKit value into this; Dash reads it back.
public enum BatteryState: String, Codable, Equatable, Sendable, CaseIterable {

    /// The state can't be determined (monitoring off, simulator).
    case unknown

    /// On battery power, discharging.
    case unplugged

    /// Plugged in and charging (below 100%).
    case charging

    /// Plugged in at 100%.
    case full

    /// Whether the device is connected to external power.
    public var isPluggedIn: Bool {
        self == .charging || self == .full
    }
}
