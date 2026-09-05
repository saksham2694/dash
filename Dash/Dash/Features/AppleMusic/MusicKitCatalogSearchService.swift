//
//  MusicKitCatalogSearchService.swift
//  Dash — Apple Music feature
//
//  The production `MusicCatalogSearchService` — a single
//  `MusicCatalogSearchRequest` covering songs, albums, artists and playlists
//  in one round trip.
//

import Foundation
import MusicKit

struct MusicKitCatalogSearchService: MusicCatalogSearchService {

    func search(term: String, limit: Int = 25) async throws -> MusicCatalogSearchResults {
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return MusicCatalogSearchResults()
        }
        var request = MusicCatalogSearchRequest(
            term: term,
            types: [Song.self, Album.self, Artist.self, Playlist.self]
        )
        request.limit = limit
        let response = try await request.response()
        return MusicCatalogSearchResults(
            songs: response.songs,
            albums: response.albums,
            artists: response.artists,
            playlists: response.playlists
        )
    }

    func song(withID id: MusicItemID) async throws -> Song? {
        var request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id)
        request.limit = 1
        let response = try await request.response()
        return response.items.first
    }

    func songs(withIDs ids: [MusicItemID]) async throws -> MusicItemCollection<Song> {
        guard !ids.isEmpty else { return [] }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids)
        return try await request.response().items
    }
}
