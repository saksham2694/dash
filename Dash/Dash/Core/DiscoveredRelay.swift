//
//  DiscoveredRelay.swift
//  Dash
//
//  A DashRelay instance currently visible on the network. This is a *transient
//  discovery result* — distinct from `KnownRelay`, which is a device the iPad has
//  been told to remember. Discovery comes and goes as the phone appears/leaves;
//  pairing does not.
//
//  Identity is the stable relay id from the Bonjour TXT record
//  (`RelayAdvertisement.id`), never the Bonjour service name.
//

import Foundation

struct DiscoveredRelay: Equatable, Identifiable, Sendable {

    /// Stable relay identity (TXT `rid`). Matches `KnownRelay.id` when paired.
    let id: String

    /// Human-readable device name from the advertisement.
    let displayName: String

    /// A short, glanceable slice of the id, for telling apart two relays that
    /// advertise the same name.
    var shortID: String { String(id.prefix(6)) }
}
