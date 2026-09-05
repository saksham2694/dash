//
//  MusicCollectionRows.swift
//  Dash — Apple Music feature
//
//  Plain row presentations for albums/artists/playlists — shared by Search
//  and Library so both look identical. Songs have their own richer
//  `MusicSongRow` (a favorite heart, plays on tap); these three are simpler
//  since tapping them navigates to a detail/track list instead.
//

import MusicKit
import SwiftUI

struct MusicAlbumRow: View {

    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = album.artwork {
                ArtworkImage(artwork, width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MusicTheme.cardFill)
                    .frame(width: 44, height: 44)
                    .overlay { Image(systemName: "square.stack").foregroundStyle(MusicTheme.textTertiary) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MusicTheme.textPrimary)
                    .lineLimit(1)
                Text(album.artistName)
                    .font(.caption)
                    .foregroundStyle(MusicTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

struct MusicArtistRow: View {

    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = artist.artwork {
                ArtworkImage(artwork, width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(MusicTheme.cardFill)
                    .frame(width: 44, height: 44)
                    .overlay { Image(systemName: "music.mic").foregroundStyle(MusicTheme.textTertiary) }
            }
            Text(artist.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MusicTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

struct MusicPlaylistRow: View {

    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = playlist.artwork {
                ArtworkImage(artwork, width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MusicTheme.cardFill)
                    .frame(width: 44, height: 44)
                    .overlay { Image(systemName: "music.note.list").foregroundStyle(MusicTheme.textTertiary) }
            }
            Text(playlist.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MusicTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}
