//
//  DestinationStore.swift
//  Dash
//
//  The single source of truth for "where is the driver headed" — one SDK-neutral
//  `Destination?`, held apart from both the search UI (which is transient) and the
//  map renderer (which just draws what it is told). Routing / trip features will
//  read from here later.
//
//  Mirrors the project's pattern of small single-purpose stores
//  (`LocationStore`, `KnownDeviceStore`).
//

import Combine
import Foundation

@MainActor
final class DestinationStore: ObservableObject {

    /// The chosen destination, or `nil` when the driver is just cruising.
    @Published private(set) var destination: Destination?

    var hasDestination: Bool { destination != nil }

    init(destination: Destination? = nil) {
        self.destination = destination
    }

    func select(_ destination: Destination) {
        self.destination = destination
    }

    func clear() {
        destination = nil
    }
}
