//
//  MusicLibraryView.swift
//  Dash — Apple Music feature
//
//  M9.0 §"Library" — four initial categories (Songs, Albums, Artists,
//  Playlists), kept focused rather than reproducing every Apple Music
//  library screen.
//

import MusicKit
import SwiftUI

nonisolated enum MusicLibraryCategory: String, Identifiable, CaseIterable, Hashable {
    case songs, albums, artists, playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs:     return "Songs"
        case .albums:    return "Albums"
        case .artists:   return "Artists"
        case .playlists: return "Playlists"
        }
    }

    var symbolName: String {
        switch self {
        case .songs:     return "music.note"
        case .albums:    return "square.stack"
        case .artists:   return "music.mic"
        case .playlists: return "music.note.list"
        }
    }
}

struct MusicLibraryView: View {

    let feature: AppleMusicFeature
    @ObservedObject private var libraryViewModel: MusicLibraryViewModel

    init(feature: AppleMusicFeature) {
        self.feature = feature
        _libraryViewModel = ObservedObject(wrappedValue: feature.libraryViewModel)
    }

    var body: some View {
        List {
            ForEach(MusicLibraryCategory.allCases) { category in
                NavigationLink(value: category) {
                    Label(category.title, systemImage: category.symbolName)
                        .foregroundStyle(MusicTheme.textPrimary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MusicTheme.background)
        .navigationTitle("Library")
        .navigationDestination(for: MusicLibraryCategory.self) { category in
            MusicLibraryCategoryView(feature: feature, category: category)
        }
        .task { await libraryViewModel.loadIfNeeded() }
        .refreshable { await libraryViewModel.reload() }
    }
}

private struct MusicLibraryCategoryView: View {

    let feature: AppleMusicFeature
    let category: MusicLibraryCategory
    @ObservedObject private var libraryViewModel: MusicLibraryViewModel

    init(feature: AppleMusicFeature, category: MusicLibraryCategory) {
        self.feature = feature
        self.category = category
        _libraryViewModel = ObservedObject(wrappedValue: feature.libraryViewModel)
    }

    var body: some View {
        Group {
            if libraryViewModel.isLoading && isCategoryEmpty {
                ProgressView().tint(MusicTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isCategoryEmpty {
                ContentUnavailableView("No \(category.title)", systemImage: category.symbolName)
            } else {
                list
            }
        }
        .background(MusicTheme.background)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Album.self) { MusicAlbumDetailView(feature: feature, album: $0) }
        .navigationDestination(for: Playlist.self) { MusicPlaylistDetailView(feature: feature, playlist: $0) }
    }

    private var isCategoryEmpty: Bool {
        switch category {
        case .songs:     return libraryViewModel.songs.isEmpty
        case .albums:    return libraryViewModel.albums.isEmpty
        case .artists:   return libraryViewModel.artists.isEmpty
        case .playlists: return libraryViewModel.playlists.isEmpty
        }
    }

    @ViewBuilder
    private var list: some View {
        List {
            switch category {
            case .songs:
                ForEach(libraryViewModel.songs) { song in
                    MusicSongRow(song: song, favoritesStore: feature.favoritesStore) {
                        Task { await feature.playerViewModel.play(Array(libraryViewModel.songs), startingAt: song) }
                    }
                }
            case .albums:
                ForEach(libraryViewModel.albums) { album in
                    NavigationLink(value: album) { MusicAlbumRow(album: album) }
                }
            case .artists:
                ForEach(libraryViewModel.artists) { artist in
                    MusicArtistRow(artist: artist)
                }
            case .playlists:
                ForEach(libraryViewModel.playlists) { playlist in
                    NavigationLink(value: playlist) { MusicPlaylistRow(playlist: playlist) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
