//
//  MusicKitSubscriptionService.swift
//  Dash — Apple Music feature
//
//  The production `MusicSubscriptionService` — Apple `MusicKit`'s
//  `MusicSubscription`. The actual "subscribe" UI is Apple's own native
//  sheet (the `.musicSubscriptionOffer(...)` view modifier, applied directly
//  in `AppleMusicRootView`) — never a custom purchase flow.
//

import MusicKit

struct MusicKitSubscriptionService: MusicSubscriptionService {

    func currentStatus() async -> MusicSubscriptionStatus {
        guard let subscription = try? await MusicSubscription.current else {
            return .unknown
        }
        return MusicSubscriptionStatus(
            canPlayCatalogContent: subscription.canPlayCatalogContent,
            canBecomeSubscriber: subscription.canBecomeSubscriber
        )
    }
}
