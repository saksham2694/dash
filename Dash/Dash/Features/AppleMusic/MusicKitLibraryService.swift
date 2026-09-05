//
//  MusicKitLibraryService.swift
//  Dash — Apple Music feature
//
//  The production `MusicLibraryService` — plain `MusicLibraryRequest`s
//  against the user's library, and the `.tracks` relationship for an album
//  or playlist. Requires Apple Music authorization (`MusicAuthorizationService`);
//  callers are expected to have already checked that.
//

import Foundation
import MusicKit

struct MusicKitLibraryService: MusicLibraryService {

    func songs(limit: Int = 100) async throws -> MusicItemCollection<Song> {
        var request = MusicLibraryRequest<Song>()
        request.limit = limit
        request.sort(by: \.libraryAddedDate, ascending: false)
        return try await request.response().items
    }

    func albums(limit: Int = 100) async throws -> MusicItemCollection<Album> {
        var request = MusicLibraryRequest<Album>()
        request.limit = limit
        return try await request.response().items
    }

    func artists(limit: Int = 100) async throws -> MusicItemCollection<Artist> {
        var request = MusicLibraryRequest<Artist>()
        request.limit = limit
        return try await request.response().items
    }

    func playlists(limit: Int = 100) async throws -> MusicItemCollection<Playlist> {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = limit
        return try await request.response().items
    }

    func tracks(of album: Album) async throws -> MusicItemCollection<Track> {
        let detailed = try await album.with(.tracks)
        return detailed.tracks ?? []
    }

    func tracks(of playlist: Playlist) async throws -> MusicItemCollection<Track> {
        let detailed = try await playlist.with(.tracks)
        return detailed.tracks ?? []
    }
}
