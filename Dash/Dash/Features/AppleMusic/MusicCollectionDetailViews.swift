//
//  MusicCollectionDetailViews.swift
//  Dash — Apple Music feature
//
//  Track lists for one album or playlist — reached from Search or Library.
//  Tapping a track plays the WHOLE collection's tracks, starting there, so
//  next/previous naturally move through the rest of the album/playlist.
//

import MusicKit
import SwiftUI

struct MusicAlbumDetailView: View {

    let feature: AppleMusicFeature
    let album: Album

    @State private var tracks: MusicItemCollection<Track> = []
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            Section("Tracks") {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, index: index)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MusicTheme.background)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            tracks = (try? await feature.tracks(of: album)) ?? []
            isLoading = false
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            if let artwork = album.artwork {
                ArtworkImage(artwork, width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Text(album.title).font(.headline).foregroundStyle(MusicTheme.textPrimary).multilineTextAlignment(.center)
            Text(album.artistName).font(.subheadline).foregroundStyle(MusicTheme.textSecondary)
        }
        .padding(.vertical, 12)
    }

    private func trackRow(_ track: Track, index: Int) -> some View {
        Button {
            Task { await feature.playerViewModel.play(Array(tracks), startingAt: track) }
        } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(MusicTheme.textTertiary)
                    .frame(width: 24, alignment: .trailing)
                Text(track.title)
                    .font(.subheadline)
                    .foregroundStyle(MusicTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MusicPlaylistDetailView: View {

    let feature: AppleMusicFeature
    let playlist: Playlist

    @State private var tracks: MusicItemCollection<Track> = []
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            Section("Songs") {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    trackRow(track, index: index)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MusicTheme.background)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            tracks = (try? await feature.tracks(of: playlist)) ?? []
            isLoading = false
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            if let artwork = playlist.artwork {
                ArtworkImage(artwork, width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Text(playlist.name).font(.headline).foregroundStyle(MusicTheme.textPrimary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
    }

    private func trackRow(_ track: Track, index: Int) -> some View {
        Button {
            Task { await feature.playerViewModel.play(Array(tracks), startingAt: track) }
        } label: {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(MusicTheme.textTertiary)
                    .frame(width: 24, alignment: .trailing)
                Text(track.title)
                    .font(.subheadline)
                    .foregroundStyle(MusicTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
