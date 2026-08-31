//
//  ConnectionState.swift
//  Dash
//
//  The app-level vocabulary for the link to DashRelay. Kept separate from the
//  transport's own `LocationReceiver.Status.Phase` so the rest of the app depends
//  on this stable concept, not on a networking detail.
//

/// Where the connection to DashRelay currently is.
enum ConnectionState: Equatable {
    /// Not connected and not trying (fresh launch, or after a deliberate disconnect).
    case disconnected
    /// Browsing Bonjour for a DashRelay service.
    case discovering
    /// Found a relay, opening the TCP connection.
    case connecting
    /// Connected and receiving (or ready to receive) location packets.
    case connected
}
