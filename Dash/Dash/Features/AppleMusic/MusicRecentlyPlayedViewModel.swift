//
//  MusicRecentlyPlayedViewModel.swift
//  Dash — Apple Music feature
//
//  M9.0 §"Recently played" against `MusicRecentlyPlayedService`.
//

import Combine
import Foundation
import MusicKit

@MainActor
final class MusicRecentlyPlayedViewModel: ObservableObject {

    @Published private(set) var songs: MusicItemCollection<Song> = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private(set) var loadedOnce = false
    private let service: any MusicRecentlyPlayedService

    init(service: any MusicRecentlyPlayedService) {
        self.service = service
    }

    func loadIfNeeded() async {
        guard !loadedOnce else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        loadError = nil
        do {
            songs = try await service.recentlyPlayedSongs(limit: 30)
        } catch {
            loadError = "Couldn’t load recently played songs."
        }
        isLoading = false
        loadedOnce = true
    }
}
