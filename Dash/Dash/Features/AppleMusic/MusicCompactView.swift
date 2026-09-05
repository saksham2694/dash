//
//  MusicCompactView.swift
//  Dash — Apple Music feature
//
//  The compact dashboard widget (M9.0 §"Widgets"): song title + artist on
//  the left, artwork on the right up top, previous/play-pause/next
//  underneath. Controls operate directly on the shared `MusicPlayerViewModel`;
//  pressing one never opens the full app — only the widget's own background
//  (handled by `WidgetHostView`, outside this view) does that.
//
//  Physical-test fix: artwork was too small to recognize at a glance and the
//  gap above the transport row read as too tight. Artwork is bigger (44→60pt)
//  and the row spacing grew (10→16pt) to match; the metadata column narrows
//  to make room and truncates with a single line + tail ellipsis rather than
//  wrapping or squeezing, so a long title/artist never breaks the layout.
//

import MusicKit
import SwiftUI

struct MusicCompactView: View {

    @ObservedObject var playerViewModel: MusicPlayerViewModel
    @ObservedObject var accessViewModel: MusicAccessViewModel

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                artwork
            }

            MusicTransportControls(playerViewModel: playerViewModel, iconSize: 15, playIconSize: 22, spacing: 20)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MusicTheme.widgetSurfaceTint)
    }

    private var title: String {
        guard accessViewModel.isAuthorized else { return "Apple Music" }
        return playerViewModel.currentEntry?.title ?? "Not Playing"
    }

    private var subtitle: String {
        guard accessViewModel.isAuthorized else { return "Tap to connect" }
        return playerViewModel.currentEntry?.subtitle ?? " "
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = playerViewModel.currentEntry?.artwork {
            ArtworkImage(art, width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(MusicTheme.cardFill)
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                }
        }
    }
}
