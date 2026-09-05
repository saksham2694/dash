//
//  MusicTransportControls.swift
//  Dash — Apple Music feature
//
//  The previous / play-pause / next row shared by every widget size and the
//  full Now Playing screen — one control implementation instead of three
//  near-duplicates.
//
//  Every button here calls straight into the shared `MusicPlayerViewModel`
//  (never `onOpenFeature`) — pressing one must never open the full app
//  (M9.0 §"Widgets"). Plain `.buttonStyle(.plain)` on each button is
//  deliberate: it keeps these as independently-hit-testable controls nested
//  inside the dashboard's own whole-tile tap target.
//

import SwiftUI

struct MusicTransportControls: View {

    @ObservedObject var playerViewModel: MusicPlayerViewModel
    var iconSize: CGFloat = 18
    var playIconSize: CGFloat = 26
    var spacing: CGFloat = 22

    var body: some View {
        HStack(spacing: spacing) {
            Button {
                Task { await playerViewModel.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: iconSize, weight: .semibold))
            }

            Button {
                Task { await playerViewModel.togglePlayPause() }
            } label: {
                Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: playIconSize, weight: .semibold))
            }

            Button {
                Task { await playerViewModel.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: iconSize, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}
