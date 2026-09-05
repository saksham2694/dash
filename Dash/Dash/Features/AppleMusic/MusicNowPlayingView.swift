//
//  MusicNowPlayingView.swift
//  Dash — Apple Music feature
//
//  The full Now Playing screen (M9.0 §"Full-screen app" / §"Design": "should
//  visually resemble the Apple Music Now Playing experience") — large
//  artwork, title/artist, a scrubbable progress bar, transport controls, a
//  favorite heart, and the real system volume control. Reads the SAME
//  `MusicPlayerViewModel` every widget size does.
//
//  The volume row uses the SAME `SystemVolumeSlider` (an `MPVolumeView`
//  wrapper) the large widget used to — not a second implementation, and
//  deliberately not wired to `MusicPlayerViewModel` at all: MusicKit doesn't
//  own system volume, so this stays a plain platform control that changes
//  the real device volume directly. (The large widget's own volume is now a
//  separate, display-only indicator — see `MusicVolumeIndicatorView.swift`;
//  this screen's is the one real, interactive volume control left.)
//
//  M9.0 final interaction cleanup — swipe down to dismiss: presented via
//  `AppleMusicRootView`'s `.fullScreenCover`, which already gives a plain
//  down-chevron button. This adds a `DragGesture` so a downward swipe
//  anywhere on the screen ALSO dismisses it, the way Apple Music's own
//  sheet/player does. Attached as `.simultaneousGesture` (not `.gesture`)
//  specifically so it never competes for the touch with any descendant
//  control — the progress `Slider`, the transport `Button`s, and especially
//  `SystemVolumeSlider` (a real `MPVolumeView`/UIKit bridge, the one kind of
//  control this session repeatedly found doesn't arbitrate against ordinary
//  SwiftUI ancestor gestures the normal way) all keep receiving their own
//  touches exactly as before; this gesture only ever *also* watches the same
//  touch stream and decides independently, at the end, whether it was a
//  clearly-downward swipe worth dismissing for. A `minimumDistance` of 24
//  plus a translation/direction threshold in `onEnded` means an ordinary tap,
//  or a mostly-horizontal drag (seeking, the volume slider), never dismisses.
//

import MusicKit
import SwiftUI

struct MusicNowPlayingView: View {

    @ObservedObject var playerViewModel: MusicPlayerViewModel
    @ObservedObject var favoritesStore: MusicFavoritesStore

    @Environment(\.dismiss) private var dismiss

    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0

    /// How far down a swipe must travel, and how much it must dominate any
    /// sideways movement, before it counts as "dismiss" rather than an
    /// incidental diagonal touch on a control. Not `private` so tests can
    /// exercise the decision rule without a live gesture.
    static let dismissDistance: CGFloat = 110
    static let dismissDirectionRatio: CGFloat = 1.5

    var body: some View {
        VStack(spacing: 28) {
            artwork

            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MusicTheme.textPrimary)
                        .lineLimit(1)
                    if let song = currentSong {
                        favoriteButton(for: song)
                    }
                }
                Text(artist)
                    .font(.headline)
                    .foregroundStyle(MusicTheme.textSecondary)
                    .lineLimit(1)
            }

            progressSection
            controls
            volumeRow
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MusicTheme.background)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if Self.isDismissSwipe(translation: value.translation) {
                        dismiss()
                    }
                }
        )
    }

    /// Pure decision rule behind the swipe-to-dismiss gesture — see this
    /// file's header. A clearly-downward, mostly-vertical drag dismisses; a
    /// short, sideways, or upward one never does.
    static func isDismissSwipe(translation: CGSize) -> Bool {
        translation.height > dismissDistance
            && translation.height > abs(translation.width) * dismissDirectionRatio
    }

    private var currentSong: Song? { playerViewModel.currentEntry?.item as? Song }
    private var title: String { playerViewModel.currentEntry?.title ?? "Not Playing" }
    private var artist: String { playerViewModel.currentEntry?.subtitle ?? "" }

    @ViewBuilder
    private var artwork: some View {
        if let art = playerViewModel.currentEntry?.artwork {
            ArtworkImage(art, width: 260, height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MusicTheme.cardFill)
                .frame(width: 260, height: 260)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundStyle(MusicTheme.textTertiary)
                }
        }
    }

    private func favoriteButton(for song: Song) -> some View {
        let isFavorite = favoritesStore.isFavorite(song)
        return Button {
            favoritesStore.toggleFavorite(song)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(isFavorite ? MusicTheme.accent : MusicTheme.textTertiary)
        }
        .buttonStyle(.plain)
        .onAppear { favoritesStore.refreshIfNeeded(song) }
    }

    private var progressSection: some View {
        let duration = max(playerViewModel.duration ?? 1, 1)
        return VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubTime : min(playerViewModel.playbackTime, duration) },
                    set: { scrubTime = $0 }
                ),
                in: 0...duration,
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing { playerViewModel.seek(to: scrubTime) }
                }
            )
            .tint(MusicTheme.accent)

            HStack {
                Text(MusicFormatting.timeText(isScrubbing ? scrubTime : playerViewModel.playbackTime))
                Spacer()
                Text(MusicFormatting.timeText(playerViewModel.duration ?? 0))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(MusicTheme.textSecondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 44) {
            Button {
                Task { await playerViewModel.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill").font(.title)
            }

            Button {
                Task { await playerViewModel.togglePlayPause() }
            } label: {
                Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46))
            }

            Button {
                Task { await playerViewModel.skipToNext() }
            } label: {
                Image(systemName: "forward.fill").font(.title)
            }
        }
        .foregroundStyle(MusicTheme.textPrimary)
        .buttonStyle(.plain)
    }

    /// The real system volume control — changes the device's actual audio
    /// volume, not a value this view keeps track of itself.
    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(MusicTheme.textTertiary)
            SystemVolumeSlider()
                .frame(height: 24)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(MusicTheme.textTertiary)
        }
        .frame(maxWidth: 320)
    }
}
