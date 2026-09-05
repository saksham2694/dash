//
//  MusicMiniPlayerView.swift
//  Dash — Apple Music feature
//
//  The persistent, Apple-Music-style mini player (M9.0 UI pass §"Navigation
//  redesign"): anchored above the tab bar in `AppleMusicRootView`, visible on
//  every page whenever there is a current song. Reads the SAME shared
//  `MusicPlayerViewModel`/`ApplicationMusicPlayer` every other surface does —
//  no second player. Tapping the row itself (outside its own transport
//  controls) expands the full Now Playing screen; the controls act directly
//  on playback and never do that themselves — same nested-`Button`-inside-
//  `Button` pattern already used (and already working) by every dashboard
//  widget size.
//
//  Physical-test fix (M9.0 UI pass — hit-area): the empty space between the
//  metadata and the transport controls didn't expand the player. The row's
//  `HStack` had no explicit width, so its ideal (content-hugging) size — not
//  the full visible card width — was what the `Button` actually laid its
//  label out at; the `Spacer` between metadata and transport only looked
//  like it filled the row (painted over by the card's own background) but
//  wasn't really part of the Button's hit-tested frame. `.frame(maxWidth:
//  .infinity)` + `.contentShape(Rectangle())` on the label make the ENTIRE
//  visible row — Spacer included — the actual tappable area.
//

import MusicKit
import SwiftUI

struct MusicMiniPlayerView: View {

    @ObservedObject var playerViewModel: MusicPlayerViewModel
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            Button(action: onExpand) {
                HStack(spacing: 12) {
                    artwork

                    VStack(alignment: .leading, spacing: 1) {
                        Text(playerViewModel.currentEntry?.title ?? "Not Playing")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MusicTheme.textPrimary)
                            .lineLimit(1)
                        Text(playerViewModel.currentEntry?.subtitle ?? " ")
                            .font(.caption)
                            .foregroundStyle(MusicTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    MusicTransportControls(playerViewModel: playerViewModel, iconSize: 15, playIconSize: 22, spacing: 18)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 57)
        .background(MusicTheme.secondaryBackground)
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = playerViewModel.currentEntry?.artwork {
            ArtworkImage(art, width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(MusicTheme.cardFill)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(MusicTheme.textTertiary)
                }
        }
    }
}
