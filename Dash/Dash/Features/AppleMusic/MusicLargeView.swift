//
//  MusicLargeView.swift
//  Dash — Apple Music feature
//
//  The large dashboard widget (M9.0 §"Widgets") — large artwork, title,
//  artist, playback progress, previous/play/pause/next, and system volume
//  (`SystemVolumeSlider`). Visually a compact take on the Now Playing
//  screen; same shared-state / controls-never-open-the-app rules as the
//  other widget sizes.
//
//  M9.0 final interaction cleanup: this widget's volume is now
//  DISPLAY-ONLY (`SystemVolumeIndicator` — a plain SwiftUI bar reading
//  `AVAudioSession.outputVolume`, see `MusicVolumeIndicatorView.swift`), not
//  a real `MPVolumeView`. Two earlier passes tried to make a real, draggable
//  `MPVolumeView` coexist here with `WidgetHostView`'s tap-to-open `Button`
//  and the dashboard pager — physical testing kept finding it unreliable, so
//  interactive volume control was dropped from this widget entirely (the
//  full-screen player keeps the real, working one). Since there's no
//  `MPVolumeView`/UIKit bridge here anymore, a touch only needs a plain
//  `onTapGesture {}` to stay from opening the feature — the SwiftUI-vs-UIKit
//  gesture-arbitration problem that made the interactive version unreliable
//  doesn't apply to a plain SwiftUI view.
//
//  Visually, the indicator is its own separated row (icons + background
//  card) toward the bottom of the widget, distinct from the transport row
//  above it — unchanged from the interactive version's position/spacing.
//
//  Physical-test fix (M9.0 UI pass — vertical balance): artwork/metadata/
//  progress/transport were pinned to the top with a single flexible
//  `Spacer` soaking up ALL the widget's leftover height before the volume
//  row — correct internal spacing, but the group as a whole read as too
//  high, with a big empty gap above the volume control. `body` now treats
//  that whole group as one unit (`mainGroup`, its own internal spacing
//  unchanged) framed by two equal, `minLength: 0` Spacers, so it's centred
//  in the space above the volume row; the fixed gap right before the volume
//  row (`volumeTopGap`) is untouched, so the volume control's own position/
//  separation doesn't move.
//

import MusicKit
import SwiftUI

struct MusicLargeView: View {

    @ObservedObject var playerViewModel: MusicPlayerViewModel
    @ObservedObject var accessViewModel: MusicAccessViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            mainGroup

            Spacer(minLength: 0)

            // Fixed — not flexible — so the volume row's own position and
            // separation from the group above it never changes; only the
            // group's centring (the two Spacers around it) responds to the
            // widget's available height.
            Color.clear.frame(height: volumeTopGap)

            volumeControl
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MusicTheme.widgetSurfaceTint)
    }

    private let volumeTopGap: CGFloat = 22

    /// Artwork through transport controls, as one unit — see this file's
    /// header ("vertical balance"). Internal spacing between these four
    /// elements is unchanged; only where the group sits as a whole changed.
    private var mainGroup: some View {
        VStack(spacing: 0) {
            artwork

            VStack(spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            .padding(.top, 20)

            progress
                .padding(.top, 22)

            MusicTransportControls(playerViewModel: playerViewModel, iconSize: 20, playIconSize: 32, spacing: 32)
                .padding(.top, 26)
        }
    }

    /// A display-only system volume indicator — see this file's header
    /// comment. Not draggable, doesn't change the volume, and doesn't open
    /// the feature when touched.
    private var volumeControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
            SystemVolumeIndicator()
                .frame(height: 6)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .contentShape(Rectangle())
        // Absorbs the tap so it never bubbles up to `WidgetHostView`'s
        // outer tap-to-open Button — safe/reliable here since this is a
        // plain SwiftUI view with no UIKit bridge underneath (see header).
        .onTapGesture {}
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
            ArtworkImage(art, width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MusicTheme.cardFill)
                .frame(width: 200, height: 200)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.4))
                }
        }
    }

    private var progress: some View {
        let duration = playerViewModel.duration ?? 0
        return VStack(spacing: 4) {
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
