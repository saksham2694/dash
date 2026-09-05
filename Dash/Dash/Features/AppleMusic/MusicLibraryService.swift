//
//  MusicLibraryService.swift
//  Dash — Apple Music feature
//
//  The seam around `MusicLibraryRequest` (M9.0 §"Library"). Four initial
//  categories, per instruction — kept focused rather than reproducing every
//  Apple Music library screen.
//

import Foundation
import MusicKit

protocol MusicLibraryService: Sendable {
    func songs(limit: Int) async throws -> MusicItemCollection<Song>
    func albums(limit: Int) async throws -> MusicItemCollection<Album>
    func artists(limit: Int) async throws -> MusicItemCollection<Artist>
    func playlists(limit: Int) async throws -> MusicItemCollection<Playlist>

    /// The tracks inside one album — used when the user drills into a
    /// library or search result album.
    func tracks(of album: Album) async throws -> MusicItemCollection<Track>

    /// The songs inside one playlist.
    func tracks(of playlist: Playlist) async throws -> MusicItemCollection<Track>
}
