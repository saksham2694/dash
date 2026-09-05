//
//  MusicMediumView.swift
//  Dash — Apple Music feature
//
//  The medium dashboard widget (M9.0 §"Widgets"). Physical-test fix: this
//  was a horizontal mini-player-style row (artwork beside the metadata) —
//  that's not what was wanted. It's now the SAME vertical composition as the
//  large widget and the full Now Playing screen — artwork above metadata
//  above progress above transport — just proportionately scaled down for the
//  medium footprint (no volume control; large-widget-only). Same shared-
//  state / controls-never-open-the-app rules as every other widget size.
//

import MusicKit
import SwiftUI

struct MusicMediumView: View {

    @ObservedObject var playerViewModel: MusicPlayerViewModel
    @ObservedObject var accessViewModel: MusicAccessViewModel

    var body: some View {
        VStack(spacing: 0) {
            artwork

            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .padding(.top, 10)

            progress
                .padding(.top, 10)

            MusicTransportControls(playerViewModel: playerViewModel, iconSize: 16, playIconSize: 26, spacing: 24)
                .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MusicTheme.widgetSurfaceTint)
    }

    private var title: String {
        guard accessViewModel.isAuthorized else { return "Apple Music" }
        return playerViewModel.currentEntry?.title ?? "Not Playing"
    }

    private var subtitle: String {
        guard accessViewModel.isAuthorized else { return "Tap to connect your account" }
        return playerViewModel.currentEntry?.subtitle ?? " "
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = playerViewModel.currentEntry?.artwork {
            ArtworkImage(art, width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(MusicTheme.cardFill)
                .frame(width: 84, height: 84)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.4))
                }
        }
    }

    private var progress: some View {
        let duration = playerViewModel.duration ?? 0
        return VStack(spacing: 3) {
            ProgressView(value: MusicFormatting.progress(time: playerViewModel.playbackTime, duration: playerViewModel.duration))
                .tint(MusicTheme.accent)
            HStack {
                Text(MusicFormatting.timeText(playerViewModel.playbackTime))
                Spacer()
                Text(MusicFormatting.timeText(duration))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}
