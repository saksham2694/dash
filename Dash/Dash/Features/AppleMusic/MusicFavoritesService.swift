//
//  MusicFavoritesService.swift
//  Dash — Apple Music feature
//
//  The seam around favoriting a song (M9.0 §"Favorites"). MusicKit's
//  strongly-typed Swift API only exposes one-directional "add to library"
//  (`MusicLibrary.shared.add`, no supported remove) — not a bidirectional
//  heart/love toggle. The real Apple Music "Love" is the `v1/me/ratings/songs`
//  endpoint, which MusicKit exposes via `MusicDataRequest` — the sanctioned
//  escape hatch for endpoints not yet wrapped in a typed Swift API. That's
//  what `MusicKitFavoritesService` uses, so "favorite" here means the same
//  thing the heart icon in Apple Music means.
//

import Foundation
import MusicKit

protocol MusicFavoritesService: Sendable {
    func isFavorite(songID: MusicItemID) async -> Bool
    func setFavorite(songID: MusicItemID, isFavorite: Bool) async throws
}
