//
//  LocationReceiver.swift
//  Dash
//
//  The iPad side of the GPS link. Discovers DashRelay companion apps via Bonjour,
//  reads each one's identity from its TXT record, and — once the connection layer
//  picks a target — opens a TCP connection to that specific relay and decodes the
//  newline-delimited JSON stream into `LocationPacket` values.
//
//  It is the *only* thing that touches the network. It does not decide which
//  relay to use: `ConnectionCoordinator` calls `setTargetRelay(id:)`. After an
//  incidental drop it reconnects **only to that target**, never to whatever else
//  happens to be nearby (spec §4).
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
        /// The stable relay id we are connected to, once `phase == .connected`.
        /// `nil` otherwise.
        var connectedRelayID: String?
        /// The connected relay's human-readable name, for display. `nil` unless
        /// connected.
        var connectedDisplayName: String?
    }

    /// Called on the main actor for every decoded packet, in arrival order.
    var onPacket: (@MainActor @Sendable (LocationPacket) -> Void)?

    /// Called on the main actor whenever `Status` changes.
    var onStatusChange: (@MainActor @Sendable (Status) -> Void)?

    /// Called on the main actor whenever the visible relay set changes.
    var onDiscoveryChange: (@MainActor @Sendable ([DiscoveredRelay]) -> Void)?

    private let queue = DispatchQueue(label: "com.sakshamsharma.Dash.receiver")
    private let reconnectDelay: TimeInterval

    private var isActive = false
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var lineBuffer = PacketLineBuffer()
    private var reconnectWorkItem: DispatchWorkItem?
    private var status = Status()

    /// The relay the connection layer wants us pinned to. `nil` ⇒ browse only.
    private var targetRelayID: String?

    /// Everything Bonjour currently sees, keyed by stable relay id.
    private var discovered: [String: Discovered] = [:]

    /// The relay we are currently opening / holding a connection to.
    private var pendingRelay: Discovered?

    private struct Discovered: Sendable {
        let advertisement: RelayAdvertisement
        let endpoint: NWEndpoint
    }

    init(reconnectDelay: TimeInterval = 2) {
        self.reconnectDelay = reconnectDelay
    }

    // MARK: - Lifecycle

    /// Begin discovering. Does not connect until `setTargetRelay(id:)` names one.
    /// Safe to call more than once.
    func start() {
        queue.async { [self] in
            guard !isActive else { return }
            isActive = true
            startBrowsing()
        }
    }

    /// Stop everything, drop the connection, and clear the target. Safe anytime.
    func stop() {
        queue.async { [self] in
            isActive = false
            targetRelayID = nil
            cancelReconnect()
            closeConnection()
            browser?.cancel()
            browser = nil
            lineBuffer.reset()
            discovered.removeAll()
            emitDiscovery()
            updateStatus { $0 = Status() }
        }
    }

    func setTargetRelay(id: String?) {
        queue.async { [self] in
            guard targetRelayID != id else { return }
            targetRelayID = id

            // Drop a connection that no longer matches the target.
            if connection != nil, status.connectedRelayID != id {
                closeConnection()
                lineBuffer.reset()
                updateStatus {
                    $0.phase = self.isActive ? .browsing : .stopped
                    $0.connectedRelayID = nil
                    $0.connectedDisplayName = nil
                }
                if isActive { startBrowsing() }
            }

            connectToTargetIfPossible()
        }
    }

    // MARK: - Wire framing (pure, testable)

    /// A `JSONDecoder` matching the relay's encoder (same `.iso8601` strategy).
    static func makeDecoder() -> JSONDecoder { LocationWireFormat.makeDecoder() }

    // MARK: - Bonjour discovery (queue-confined)

    private func startBrowsing() {
        guard isActive, browser == nil, connection == nil else { return }

        // `.bonjourWithTXTRecord` (not plain `.bonjour`) — the plain descriptor is
        // PTR-only and delivers every result with `metadata == .none`, so the
        // relay's identity TXT record (`rid` / `name`) never reaches us. This
        // descriptor asks the framework to resolve and attach the TXT record to
        // each result's `metadata`.
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
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
        var seen: [String: Discovered] = [:]
        for result in results {
            guard let advertisement = Self.advertisement(from: result) else { continue }
            seen[advertisement.id] = Discovered(advertisement: advertisement, endpoint: result.endpoint)
        }
        discovered = seen
        emitDiscovery()

        connectToTargetIfPossible()
    }

    /// Pull `RelayAdvertisement` out of a browse result's Bonjour TXT metadata.
    /// Relies on the browser being created with `.bonjourWithTXTRecord` so the TXT
    /// record is present in `result.metadata`. Relays without a valid identity are
    /// ignored — they can't be matched against a `KnownRelay`.
    private static func advertisement(from result: NWBrowser.Result) -> RelayAdvertisement? {
        guard let entries = txtEntries(from: result.metadata) else { return nil }
        return RelayAdvertisement(txtRecordEntries: entries)
    }

    /// Testable seam: the raw TXT key/value pairs carried by a browse result's
    /// Bonjour metadata, or `nil` when the TXT record has not resolved yet
    /// (`metadata == .none` — the exact physical-device failure this fix
    /// addresses). Split out because `NWBrowser.Result` has no public initializer,
    /// and kept to a plain dictionary so the mapping is trivially unit-testable.
    static func txtEntries(from metadata: NWBrowser.Result.Metadata) -> [String: String]? {
        guard case let .bonjour(txt) = metadata else { return nil }
        return txt.dictionary
    }

    // MARK: - Connection (queue-confined)

    private func connectToTargetIfPossible() {
        guard isActive, connection == nil,
              let target = targetRelayID,
              let match = discovered[target] else { return }
        connect(to: match)
    }

    private func connect(to relay: Discovered) {
        browser?.cancel()
        browser = nil
        lineBuffer.reset()
        pendingRelay = relay

        let connection = NWConnection(to: relay.endpoint, using: .tcp)
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
            let relay = pendingRelay
            updateStatus {
                $0.phase = .connected
                $0.connectedRelayID = relay?.advertisement.id
                $0.connectedDisplayName = relay?.advertisement.displayName
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
        pendingRelay = nil
    }

    // MARK: - Reconnection (queue-confined)

    /// Go back to browsing after a drop. The target relay id is kept, so when it
    /// reappears we reconnect to *it* — not to whatever else is nearby.
    private func scheduleReconnect() {
        guard isActive, reconnectWorkItem == nil else { return }
        updateStatus {
            $0.phase = .browsing
            $0.connectedRelayID = nil
            $0.connectedDisplayName = nil
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

    // MARK: - Callbacks

    private func updateStatus(_ mutate: (inout Status) -> Void) {
        var newValue = status
        mutate(&newValue)
        guard newValue != status else { return }
        status = newValue
        emitStatus()
    }

    private func emitStatus() {
        let value = status
        let callback = onStatusChange
        Task { @MainActor in callback?(value) }
    }

    private func emitDiscovery() {
        let relays = discovered.values
            .map { DiscoveredRelay(id: $0.advertisement.id, displayName: $0.advertisement.displayName) }
            .sorted {
                let byName = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                return byName == .orderedSame ? $0.id < $1.id : byName == .orderedAscending
            }
        let callback = onDiscoveryChange
        Task { @MainActor in callback?(relays) }
    }
}
