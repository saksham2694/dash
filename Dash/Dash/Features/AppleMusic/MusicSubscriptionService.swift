//
//  MusicSubscriptionService.swift
//  Dash — Apple Music feature
//
//  The seam around `MusicSubscription` (M9.0 §"Subscription"). Catalog
//  playback needs an active Apple Music subscription; this is how the
//  feature finds out, without the rest of the code touching MusicKit's
//  subscription type directly.
//

import Foundation

nonisolated struct MusicSubscriptionStatus: Equatable, Sendable {
    /// Whether catalog content (search results, non-library songs) can be
    /// played right now.
    var canPlayCatalogContent: Bool
    /// Whether the person is eligible to subscribe (shown Apple's own
    /// subscribe-offer sheet when this is true and they try to play
    /// something).
    var canBecomeSubscriber: Bool

    static let unknown = MusicSubscriptionStatus(canPlayCatalogContent: false, canBecomeSubscriber: false)
}

protocol MusicSubscriptionService: Sendable {
    func currentStatus() async -> MusicSubscriptionStatus
}
