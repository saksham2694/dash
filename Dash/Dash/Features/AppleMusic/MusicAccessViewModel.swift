//
//  MusicAccessViewModel.swift
//  Dash — Apple Music feature
//
//  Whether the Music feature can actually do anything right now:
//  authorization (M9.0 §"Authorization / capabilities") and subscription
//  status (M9.0 §"Subscription"). Every gated view/widget reads this instead
//  of touching `MusicAuthorizationService` / `MusicSubscriptionService`
//  directly.
//

import Combine
import Foundation

@MainActor
final class MusicAccessViewModel: ObservableObject {

    @Published private(set) var authorizationStatus: MusicAccessStatus
    @Published private(set) var subscription: MusicSubscriptionStatus = .unknown
    /// Bound to `.musicSubscriptionOffer(isPresented:)` in `AppleMusicRootView`
    /// — Apple's own native "Get Apple Music" sheet, never a custom flow.
    @Published var showingSubscriptionOffer = false

    private let authService: any MusicAuthorizationService
    private let subscriptionService: any MusicSubscriptionService

    var isAuthorized: Bool { authorizationStatus == .authorized }
    var canPlayCatalogContent: Bool { subscription.canPlayCatalogContent }

    init(authService: any MusicAuthorizationService, subscriptionService: any MusicSubscriptionService) {
        self.authService = authService
        self.subscriptionService = subscriptionService
        self.authorizationStatus = authService.currentStatus
    }

    /// Called from the access-gate view's button — requests authorization if
    /// it hasn't been decided yet, then checks subscription status.
    func requestAccessIfNeeded() async {
        if authorizationStatus == .notDetermined {
            authorizationStatus = await authService.requestAccess()
        }
        if authorizationStatus == .authorized {
            await refreshSubscription()
        }
    }

    func refreshSubscription() async {
        subscription = await subscriptionService.currentStatus()
    }
}
