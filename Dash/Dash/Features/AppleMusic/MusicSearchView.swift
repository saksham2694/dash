//
//  MusicSearchView.swift
//  Dash — Apple Music feature
//
//  M9.0 §"Search" — songs, albums, artists, playlists in one results list.
//  Tapping a song plays it immediately (queued with the rest of the songs
//  section, so next/previous move through the other results).
//

import MusicKit
import SwiftUI

struct MusicSearchView: View {

    let feature: AppleMusicFeature
    @ObservedObject private var searchViewModel: MusicSearchViewModel

    init(feature: AppleMusicFeature) {
        self.feature = feature
        _searchViewModel = ObservedObject(wrappedValue: feature.searchViewModel)
    }

    var body: some View {
        List {
            if !searchViewModel.results.songs.isEmpty {
                Section("Songs") {
                    ForEach(searchViewModel.results.songs) { song in
                        MusicSongRow(song: song, favoritesStore: feature.favoritesStore) {
                            Task { await feature.playerViewModel.play(Array(searchViewModel.results.songs), startingAt: song) }
                        }
                    }
                }
            }
            if !searchViewModel.results.albums.isEmpty {
                Section("Albums") {
                    ForEach(searchViewModel.results.albums) { album in
                        NavigationLink(value: album) { MusicAlbumRow(album: album) }
                    }
                }
            }
            if !searchViewModel.results.artists.isEmpty {
                Section("Artists") {
                    ForEach(searchViewModel.results.artists) { artist in
                        MusicArtistRow(artist: artist)
                    }
                }
            }
            if !searchViewModel.results.playlists.isEmpty {
                Section("Playlists") {
                    ForEach(searchViewModel.results.playlists) { playlist in
                        NavigationLink(value: playlist) { MusicPlaylistRow(playlist: playlist) }
                    }
                }
            }

            if let errorMessage = searchViewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(MusicTheme.textSecondary)
                    .listRowBackground(Color.clear)
            } else if searchViewModel.results.isEmpty && !searchViewModel.searchTerm.isEmpty && !searchViewModel.isSearching {
                ContentUnavailableView.search(text: searchViewModel.searchTerm)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MusicTheme.background)
        .navigationTitle("Search")
        .searchable(text: $searchViewModel.searchTerm, prompt: "Artists, Songs, Lyrics, and More")
        .navigationDestination(for: Album.self) { MusicAlbumDetailView(feature: feature, album: $0) }
        .navigationDestination(for: Playlist.self) { MusicPlaylistDetailView(feature: feature, playlist: $0) }
    }
}
