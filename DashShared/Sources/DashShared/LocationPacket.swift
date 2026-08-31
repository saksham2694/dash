import Foundation

/// A single GPS fix relayed from the iPhone companion app (DashRelay) to the
/// iPad dashboard app (Dash) over the local network.
///
/// This is the wire format shared by both apps. It lives in `DashShared` so the
/// sender and receiver can never silently drift apart. Keep it small and
/// platform-independent — no CoreLocation, UIKit, or other platform imports.
public struct LocationPacket: Codable, Equatable, Sendable {
    /// Latitude in degrees (WGS 84).
    public var latitude: Double

    /// Longitude in degrees (WGS 84).
    public var longitude: Double

    /// Speed in metres per second. Negative if the underlying fix is invalid,
    /// matching `CLLocation.speed` semantics.
    public var speed: Double

    /// Heading (course over ground) in degrees, clockwise from true north.
    /// Negative if unavailable, matching `CLLocation.course` semantics.
    public var heading: Double

    /// When this fix was produced on the sending device.
    public var timestamp: Date

    public init(
        latitude: Double,
        longitude: Double,
        speed: Double,
        heading: Double,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
        self.heading = heading
        self.timestamp = timestamp
    }
}
