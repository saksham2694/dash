//
//  MusicLibraryViewModel.swift
//  Dash — Apple Music feature
//
//  The four initial library categories (M9.0 §"Library") against
//  `MusicLibraryService`.
//

import Combine
import Foundation
import MusicKit

@MainActor
final class MusicLibraryViewModel: ObservableObject {

    @Published private(set) var songs: MusicItemCollection<Song> = []
    @Published private(set) var albums: MusicItemCollection<Album> = []
    @Published private(set) var artists: MusicItemCollection<Artist> = []
    @Published private(set) var playlists: MusicItemCollection<Playlist> = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private(set) var loadedOnce = false
    private let service: any MusicLibraryService

    init(service: any MusicLibraryService) {
        self.service = service
    }

    func loadIfNeeded() async {
        guard !loadedOnce else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        loadError = nil

        async let songsResult = try? service.songs(limit: 200)
        async let albumsResult = try? service.albums(limit: 200)
        async let artistsResult = try? service.artists(limit: 200)
        async let playlistsResult = try? service.playlists(limit: 200)

        songs = await songsResult ?? []
        albums = await albumsResult ?? []
        artists = await artistsResult ?? []
        playlists = await playlistsResult ?? []

        isLoading = false
        loadedOnce = true
    }
}
