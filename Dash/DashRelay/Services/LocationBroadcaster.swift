//
//  LocationBroadcaster.swift
//  DashRelay
//
//  The network half of the relay: advertises a Bonjour `_dashrelay._tcp` service,
//  accepts TCP connections from iPad dashboard clients, and pushes every
//  `LocationPacket` to all connected clients as one line of newline-delimited JSON.
//
//  It does not read GPS itself — `LocationTracker` does that and hands each fix to
//  `broadcast(_:)` via its `onPacket` callback (wired up in `DashRelayApp`).
//

import DashShared
import Foundation
import Network

/// All mutable state is confined to `queue`. The type is `@unchecked Sendable` on
/// that basis, which lets `broadcast(_:)` be called straight from Core Location's
/// main-actor delegate callback without an `await` hop.
final class LocationBroadcaster: @unchecked Sendable {

    /// The Bonjour service type both apps agree on (spec §3/§4). Defined once in
    /// `DashShared` so the relay and the dashboard can't drift apart.
    static let serviceType = LocationWireFormat.bonjourServiceType

    struct Status: Equatable, Sendable {
        var isListening = false
        var clientCount = 0
    }

    /// Delivered on the main actor whenever `isListening` or the client count changes.
    /// Consumed by `StatusView` later; nil until then.
    var onStatusChange: (@MainActor @Sendable (Status) -> Void)?

    private let serviceName: String
    /// Identity + name published in the Bonjour TXT record so the iPad can pair
    /// with *this* relay specifically (see `RelayAdvertisement` in `DashShared`).
    private let advertisement: RelayAdvertisement
    private let queue = DispatchQueue(label: "com.sakshamsharma.DashRelay.broadcaster")

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var status = Status()

    init(advertisement: RelayAdvertisement = RelayIdentity.load()) {
        self.advertisement = advertisement
        // The Bonjour instance name is user-facing but not an identity; fall back
        // to a constant when the device name is empty. Pairing keys on the TXT id.
        let name = advertisement.displayName
        self.serviceName = name.isEmpty ? "DashRelay" : name
    }

    /// The Bonjour instance name being advertised. Exposed for tests.
    var advertisedServiceName: String { serviceName }

    /// The identity being published in the TXT record. Exposed for tests.
    var advertisedIdentity: RelayAdvertisement { advertisement }

    // MARK: - Lifecycle

    /// Start advertising and listening. Safe to call more than once.
    func start() {
        queue.async { [self] in startListener() }
    }

    /// Stop advertising, drop all clients, and reset status. Safe to call anytime.
    func stop() {
        queue.async { [self] in
            for connection in connections.values { connection.cancel() }
            connections.removeAll()
            listener?.cancel()
            listener = nil
            updateStatus {
                $0.isListening = false
                $0.clientCount = 0
            }
        }
    }

    /// Encode `packet` as a single JSON line and send it to every connected client.
    /// A no-op when there are no clients.
    func broadcast(_ packet: LocationPacket) {
        queue.async { [self] in
            guard !connections.isEmpty,
                  let line = try? Self.encodeLine(packet) else { return }
            for connection in connections.values {
                connection.send(content: line, completion: .contentProcessed { _ in })
            }
        }
    }

    // MARK: - Wire framing

    /// A `JSONEncoder` configured for the shared wire format.
    static func makeEncoder() -> JSONEncoder { LocationWireFormat.makeEncoder() }

    /// One `LocationPacket` as compact JSON followed by a single `\n` delimiter.
    static func encodeLine(_ packet: LocationPacket, using encoder: JSONEncoder = LocationBroadcaster.makeEncoder()) throws -> Data {
        try LocationWireFormat.encodeLine(packet, using: encoder)
    }

    // MARK: - Listener (queue-confined)

    private func startListener() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            let txt = NWTXTRecord(advertisement.txtRecordEntries)
            listener.service = NWListener.Service(
                name: serviceName,
                type: Self.serviceType,
                domain: nil,
                txtRecord: txt.data
            )
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            updateStatus { $0.isListening = false }
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            updateStatus { $0.isListening = true }
        case .failed, .cancelled:
            listener = nil
            updateStatus { $0.isListening = false }
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.remove(id)
            default:
                break
            }
        }
        connection.start(queue: queue)
        updateStatus { $0.clientCount = connections.count }
    }

    private func remove(_ id: ObjectIdentifier) {
        guard connections.removeValue(forKey: id) != nil else { return }
        updateStatus { $0.clientCount = connections.count }
    }

    private func updateStatus(_ mutate: (inout Status) -> Void) {
        var newValue = status
        mutate(&newValue)
        guard newValue != status else { return }
        status = newValue

        let callback = onStatusChange
        Task { @MainActor in callback?(newValue) }
    }
}
