//
//  MusicSongRow.swift
//  Dash — Apple Music feature
//
//  One song row — artwork thumbnail, title/artist, a favorite heart — shared
//  by search results, library lists, favorites, and recently played, so
//  they all look and behave identically. Tapping the row plays it (M9.0
//  §"Search": "tapping a song should allow it to play immediately").
//

import MusicKit
import SwiftUI

struct MusicSongRow: View {

    let song: Song
    @ObservedObject var favoritesStore: MusicFavoritesStore
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MusicTheme.textPrimary)
                        .lineLimit(1)
                    Text(song.artistName)
                        .font(.caption)
                        .foregroundStyle(MusicTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                favoriteButton
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { favoritesStore.refreshIfNeeded(song) }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artwork = song.artwork {
            ArtworkImage(artwork, width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(MusicTheme.cardFill)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(MusicTheme.textTertiary)
                }
        }
    }

    private var favoriteButton: some View {
        let isFavorite = favoritesStore.isFavorite(song)
        return Button {
            favoritesStore.toggleFavorite(song)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(isFavorite ? MusicTheme.accent : MusicTheme.textTertiary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Unfavorite" : "Favorite")
    }
}
