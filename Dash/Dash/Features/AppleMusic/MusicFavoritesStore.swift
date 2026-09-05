//
//  MusicFavoritesStore.swift
//  Dash — Apple Music feature
//
//  App-scoped, persisted local cache of "songs the user has favorited from
//  Dash" — layered over `MusicFavoritesService` so the UI's heart icon
//  updates instantly (M9.0 §"Favorites": "the favorite state should update
//  correctly in the UI") without waiting on a round trip to Apple's
//  servers, and still shows the right state after a relaunch even if that
//  round trip hasn't happened yet.
//
//  This is a local MIRROR, not a second source of truth: on toggle, it
//  updates immediately AND fires the real MusicKit rating request; on first
//  seeing a song this session, it lazily asks the service for the real
//  state and folds that in.
//
//  The id-based methods (`isFavorite(id:)` / `setFavorite(id:isFavorite:)`)
//  are the actual bookkeeping — the `Song`-taking overloads below just
//  extract the id. MusicKit's model types (`Song` etc.) have no public
//  initializer, so this split is also what makes the bookkeeping itself
//  unit-testable without a real catalog/library round trip.
//

import Combine
import Foundation
import MusicKit

@MainActor
final class MusicFavoritesStore: ObservableObject {

    static let storageKey = "appleMusic.favorites.v1"

    @Published private(set) var favoriteSongIDs: Set<String> = []

    private let service: any MusicFavoritesService
    private let defaults: UserDefaults
    private var checkedIDs: Set<String> = []

    init(service: any MusicFavoritesService, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        self.favoriteSongIDs = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    // MARK: - Song-taking convenience (what the views actually call)

    func isFavorite(_ song: Song) -> Bool {
        isFavorite(id: song.id)
    }

    /// Toggle favorite state — updates local state (and the UI) immediately,
    /// then persists the real rating to Apple's servers best-effort.
    func toggleFavorite(_ song: Song) {
        let newValue = !isFavorite(song)
        setFavorite(id: song.id, isFavorite: newValue)

        Task {
            try? await service.setFavorite(songID: song.id, isFavorite: newValue)
        }
    }

    /// Best-effort reconciliation with the real server-side rating — called
    /// once per song the first time it's shown (e.g. in a list), so a
    /// favorite set from the real Apple Music app also shows correctly here.
    func refreshIfNeeded(_ song: Song) {
        let rawID = song.id.rawValue
        guard !checkedIDs.contains(rawID) else { return }
        checkedIDs.insert(rawID)

        Task {
            let isFavorite = await service.isFavorite(songID: song.id)
            if isFavorite {
                setFavorite(id: song.id, isFavorite: true)
            }
        }
    }

    // MARK: - Id-based bookkeeping (pure local state + persistence)

    func isFavorite(id: MusicItemID) -> Bool {
        favoriteSongIDs.contains(id.rawValue)
    }

    func setFavorite(id: MusicItemID, isFavorite: Bool) {
        if isFavorite {
            favoriteSongIDs.insert(id.rawValue)
        } else {
            favoriteSongIDs.remove(id.rawValue)
        }
        defaults.set(Array(favoriteSongIDs), forKey: Self.storageKey)
    }
}
