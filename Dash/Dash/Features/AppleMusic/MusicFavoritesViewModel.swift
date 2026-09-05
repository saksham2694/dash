//
//  MusicFavoritesViewModel.swift
//  Dash — Apple Music feature
//
//  Resolves `MusicFavoritesStore`'s persisted id set into real `Song`s to
//  show in the Favorites tab (M9.0 §"Favorites") — the store only keeps
//  ids (+ talks to `MusicFavoritesService`); this is the one place that
//  turns those ids back into displayable songs, via a catalog lookup.
//

import Combine
import Foundation
import MusicKit

@MainActor
final class MusicFavoritesViewModel: ObservableObject {

    @Published private(set) var songs: MusicItemCollection<Song> = []
    @Published private(set) var isLoading = false

    private let catalogSearch: any MusicCatalogSearchService
    private var cancellable: AnyCancellable?

    init(favoritesStore: MusicFavoritesStore, catalogSearch: any MusicCatalogSearchService) {
        self.catalogSearch = catalogSearch
        cancellable = favoritesStore.$favoriteSongIDs
            .sink { [weak self] ids in
                Task { await self?.resolve(ids: ids) }
            }
    }

    private func resolve(ids: Set<String>) async {
        guard !ids.isEmpty else {
            songs = []
            return
        }
        isLoading = true
        songs = (try? await catalogSearch.songs(withIDs: ids.map { MusicItemID($0) })) ?? []
        isLoading = false
    }
}
