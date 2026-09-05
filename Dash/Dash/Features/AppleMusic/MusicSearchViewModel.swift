//
//  MusicSearchViewModel.swift
//  Dash — Apple Music feature
//
//  Debounced Apple Music catalog search (M9.0 §"Search") against
//  `MusicCatalogSearchService`.
//

import Combine
import Foundation
import MusicKit

@MainActor
final class MusicSearchViewModel: ObservableObject {

    @Published var searchTerm: String = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var results = MusicCatalogSearchResults()
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let service: any MusicCatalogSearchService
    private var searchTask: Task<Void, Never>?

    init(service: any MusicCatalogSearchService) {
        self.service = service
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = MusicCatalogSearchResults()
            isSearching = false
            errorMessage = nil
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.performSearch(term: term)
        }
    }

    private func performSearch(term: String) async {
        isSearching = true
        errorMessage = nil
        do {
            let response = try await service.search(term: term, limit: 25)
            guard !Task.isCancelled else { return }
            results = response
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Couldn’t search Apple Music right now."
        }
        isSearching = false
    }
}
