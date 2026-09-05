//
//  MusicAccessGateView.swift
//  Dash — Apple Music feature
//
//  The shared "can't play yet" screen — no Apple Music authorization, or no
//  active subscription (M9.0 §"Authorization" / §"Subscription"). Every
//  gated surface (full-screen, and the widgets' own smaller version) shows
//  this instead of an empty or broken-looking UI.
//
//  The subscribe action uses Apple's own native offer sheet
//  (`.musicSubscriptionOffer`) — never a custom purchase flow, per
//  instruction.
//

import MusicKit
import SwiftUI

struct MusicAccessGateView: View {

    @ObservedObject var accessViewModel: MusicAccessViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(MusicTheme.accent)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(MusicTheme.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(MusicTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Button(action: primaryAction) {
                Text(buttonTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(MusicTheme.accent))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MusicTheme.background)
        .musicSubscriptionOffer(
            isPresented: $accessViewModel.showingSubscriptionOffer,
            options: MusicSubscriptionOffer.Options()
        )
    }

    private var title: String {
        accessViewModel.isAuthorized ? "Join Apple Music" : "Connect Apple Music"
    }

    private var message: String {
        accessViewModel.isAuthorized
            ? "An active Apple Music subscription is needed to search and play from the catalog."
            : "Dash needs access to your Apple Music account to search, play, and show your library."
    }

    private var buttonTitle: String {
        accessViewModel.isAuthorized ? "Get Apple Music" : "Connect"
    }

    private func primaryAction() {
        if accessViewModel.isAuthorized {
            accessViewModel.showingSubscriptionOffer = true
        } else {
            Task { await accessViewModel.requestAccessIfNeeded() }
        }
    }
}
