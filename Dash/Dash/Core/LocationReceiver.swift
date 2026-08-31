//
//  LocationReceiver.swift
//  Dash
//
//  The iPad side of the GPS link. Discovers the DashRelay companion app via
//  Bonjour, opens a TCP connection to it, and decodes the newline-delimited JSON
//  stream into `LocationPacket` values.
//
//  It is the *only* thing that touches the network. Every decoded packet is handed
//  out through `onPacket`; the future `LocationStore` will be the single consumer.
//  Disconnects are treated as routine — the receiver goes back to browsing and
//  reconnects on its own (spec §4).
//

import DashShared
import Foundation
import Network

/// All mutable state is confined to `queue`; `@unchecked Sendable` on that basis.
final class LocationReceiver: @unchecked Sendable {

    /// The Bonjour service type both apps agree on, defined once in `DashShared`.
    static let serviceType = LocationWireFormat.bonjourServiceType // "_dashrelay._tcp"

    struct Status: Equatable, Sendable {
        enum Phase: Equatable, Sendable {
            case stopped
            case browsing
            case connecting
            case connected
        }
        var phase: Phase = .stopped
        /// How many DashRelay instances Bonjour currently sees.
        var discoveredServiceCount = 0
        /// The Bonjour service name of the relay we are connected to, once
        /// `phase == .connected`. `nil` otherwise. The connection/session layer
        /// uses this to identify which device it reached (e.g. for pairing).
        var connectedServiceName: String?
    }

    /// Called on the main actor for every decoded packet, in arrival order.
    var onPacket: (@MainActor @Sendable (LocationPacket) -> Void)?

    /// Called on the main actor whenever `Status` changes. Consumed by the UI later.
    var onStatusChange: (@MainActor @Sendable (Status) -> Void)?

    private let queue = DispatchQueue(label: "com.sakshamsharma.Dash.receiver")
    private let reconnectDelay: TimeInterval

    private var isActive = false
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var lineBuffer = PacketLineBuffer()
    private var reconnectWorkItem: DispatchWorkItem?
    private var status = Status()
    private var pendingServiceName: String?

    init(reconnectDelay: TimeInterval = 2) {
        self.reconnectDelay = reconnectDelay
    }

    // MARK: - Lifecycle

    /// Begin discovering and connecting. Safe to call more than once.
    func start() {
        queue.async { [self] in
            guard !isActive else { return }
            isActive = true
            startBrowsing()
        }
    }

    /// Stop everything and drop the connection. Safe to call anytime.
    func stop() {
        queue.async { [self] in
            isActive = false
            cancelReconnect()
            closeConnection()
            browser?.cancel()
            browser = nil
            lineBuffer.reset()
            pendingServiceName = nil
            updateStatus { $0 = Status() }
        }
    }

    // MARK: - Wire framing (pure, testable)

    /// A `JSONDecoder` matching the relay's encoder (same `.iso8601` strategy).
    static func makeDecoder() -> JSONDecoder { LocationWireFormat.makeDecoder() }

    // MARK: - Bonjour discovery (queue-confined)

    private func startBrowsing() {
        guard isActive, browser == nil, connection == nil else { return }

        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: .tcp
        )
        browser.stateUpdateHandler = { [weak self] state in
            self?.handleBrowserState(state)
        }
        browser.browseResultsChangedHandler = { [weak self] (results: Set<NWBrowser.Result>, _: Set<NWBrowser.Result.Change>) in
            self?.handleBrowseResults(results)
        }
        self.browser = browser
        updateStatus { $0.phase = .browsing }
        browser.start(queue: queue)
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .failed:
            browser?.cancel()
            browser = nil
            scheduleReconnect()
        default:
            break
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        updateStatus { $0.discoveredServiceCount = results.count }

        // Already connecting/connected, or nothing found yet — nothing to do.
        guard connection == nil, let endpoint = results.first?.endpoint else { return }

        // NOTE (spec §4): with more than one DashRelay nearby this should surface a
        // picker rather than pick blindly. That's a UI concern; for now take the
        // first and let the count above drive a future chooser.
        connect(to: endpoint)
    }

    // MARK: - Connection (queue-confined)

    private func connect(to endpoint: NWEndpoint) {
        browser?.cancel()
        browser = nil
        lineBuffer.reset()

        if case let .service(name, _, _, _) = endpoint {
            pendingServiceName = name
        } else {
            pendingServiceName = nil
        }

        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state)
        }
        self.connection = connection
        updateStatus { $0.phase = .connecting }
        connection.start(queue: queue)
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            updateStatus {
                $0.phase = .connected
                $0.connectedServiceName = self.pendingServiceName
            }
            receiveNextChunk()
        case .failed, .cancelled:
            closeConnection()
            lineBuffer.reset()
            scheduleReconnect()
        default:
            break
        }
    }

    private func receiveNextChunk() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                let packets = self.lineBuffer.append(data)
                if !packets.isEmpty {
                    let deliver = self.onPacket
                    Task { @MainActor in
                        for packet in packets { deliver?(packet) }
                    }
                }
            }

            if isComplete || error != nil {
                // Peer hung up or the link broke — fold into the normal reconnect path.
                self.closeConnection()
                self.lineBuffer.reset()
                self.scheduleReconnect()
                return
            }
            self.receiveNextChunk()
        }
    }

    private func closeConnection() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    // MARK: - Reconnection (queue-confined)

    private func scheduleReconnect() {
        guard isActive, reconnectWorkItem == nil else { return }
        pendingServiceName = nil
        updateStatus {
            $0.phase = .browsing
            $0.discoveredServiceCount = 0
            $0.connectedServiceName = nil
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.startBrowsing()
        }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + reconnectDelay, execute: work)
    }

    private func cancelReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    // MARK: - Status

    private func updateStatus(_ mutate: (inout Status) -> Void) {
        var newValue = status
        mutate(&newValue)
        guard newValue != status else { return }
        status = newValue

        let callback = onStatusChange
        Task { @MainActor in callback?(newValue) }
    }
}
