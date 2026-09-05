//
//  MusicCatalogSearchService.swift
//  Dash — Apple Music feature
//
//  The seam around `MusicCatalogSearchRequest` (M9.0 §"Search"). Uses
//  MusicKit's own model types directly (`Song`/`Album`/`Artist`/`Playlist`) —
//  unlike Map, Music has exactly one provider, so there's no SDK-neutral
//  translation layer to build; the protocol boundary exists purely for
//  testability ("especially MusicKit access").
//

import Foundation
import MusicKit

nonisolated struct MusicCatalogSearchResults: Equatable, Sendable {
    var songs: MusicItemCollection<Song> = []
    var albums: MusicItemCollection<Album> = []
    var artists: MusicItemCollection<Artist> = []
    var playlists: MusicItemCollection<Playlist> = []

    var isEmpty: Bool { songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty }
}

protocol MusicCatalogSearchService: Sendable {
    func search(term: String, limit: Int) async throws -> MusicCatalogSearchResults

    /// Looks a single song up by its catalog id — used to restore the last
    /// played song across a relaunch (M9.0 §"Last played / relaunch").
    func song(withID id: MusicItemID) async throws -> Song?

    /// Looks several songs up by id at once — used to resolve
    /// `MusicFavoritesStore`'s persisted id set into real `Song`s to show
    /// (M9.0 §"Favorites").
    func songs(withIDs ids: [MusicItemID]) async throws -> MusicItemCollection<Song>
}
