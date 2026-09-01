import Foundation

/// What a DashRelay instance publishes about *itself* on the network, alongside
/// the `_dashrelay._tcp` service: a **stable identity** and a human-readable name.
///
/// It lives here, next to `LocationPacket` and `LocationWireFormat`, for the same
/// reason — the relay (which writes it into the Bonjour TXT record) and the
/// dashboard (which reads it back while browsing) must agree on the exact keys or
/// pairing silently breaks.
///
/// - `id` is the pairing identity. It never changes for the life of a DashRelay
///   install, so the iPad can recognise "the same iPhone" across launches and
///   networks. It is *not* derived from the Bonjour service name (that is a
///   transient networking detail and is identical for every relay today).
/// - `displayName` is for humans only. It may change (the user renames their
///   phone) without affecting pairing.
public struct RelayAdvertisement: Equatable, Sendable {

    /// TXT-record key carrying the stable relay identity.
    public static let idKey = "rid"

    /// TXT-record key carrying the human-readable device name.
    public static let displayNameKey = "name"

    /// Stable, install-lifetime identity for this relay. Pairing is keyed on this.
    public let id: String

    /// Human-readable device name (e.g. "Saksham's iPhone"). Display only.
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    /// Reconstruct from Bonjour TXT-record entries seen while browsing. Returns
    /// `nil` unless a non-empty `id` is present — an advertisement without a
    /// stable identity is useless for pairing and must be ignored.
    public init?(txtRecordEntries entries: [String: String]) {
        guard let id = entries[Self.idKey], !id.isEmpty else { return nil }
        self.id = id
        self.displayName = entries[Self.displayNameKey] ?? ""
    }

    /// The entries the relay should publish in its Bonjour TXT record.
    public var txtRecordEntries: [String: String] {
        [Self.idKey: id, Self.displayNameKey: displayName]
    }
}
