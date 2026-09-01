//
//  PlaceSearchViewModel.swift
//  Dash
//
//  Orchestrates destination search: debounces the query, asks a
//  `PlaceSearchService` for suggestions, and resolves the chosen one into a
//  `Destination`. Holds no SDK types and no map / destination state — it hands
//  the resolved `Destination` out through `onDestinationChosen` and the composing
//  view decides what to do with it.
//

import Combine
import Foundation

@MainActor
final class PlaceSearchViewModel: ObservableObject {

    /// Shortest query worth a lookup.
    static let minimumQueryLength = 2

    /// Generic, driver-glanceable failure text.
    static let searchFailureText = "Couldn’t search just now"
    static let resolveFailureText = "Couldn’t open that place"

    /// Bound to the search field. Editing it (re)schedules a debounced lookup.
    @Published var query: String = "" {
        didSet { queryDidChange() }
    }

    @Published private(set) var suggestions: [PlaceSuggestion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorText: String?

    /// The vehicle position, kept current by the composing view, used to bias
    /// results. `nil` before the first fix.
    var origin: MapCoordinate?

    /// Called with the resolved place when the driver picks a suggestion.
    var onDestinationChosen: (Destination) -> Void = { _ in }

    private let service: any PlaceSearchService
    private let debounce: Duration
    private(set) var pendingSearch: Task<Void, Never>?
    private var resolveTask: Task<Void, Never>?

    init(service: any PlaceSearchService, debounce: Duration = .milliseconds(300)) {
        self.service = service
        self.debounce = debounce
    }

    /// Pick a suggestion: resolve it to a full `Destination`, hand it out, and
    /// reset the field.
    func choose(_ suggestion: PlaceSuggestion) {
        resolveTask?.cancel()
        resolveTask = Task { [weak self] in
            await self?.resolve(suggestion)
        }
    }

    /// Clear the field and results without choosing anything.
    func reset() {
        pendingSearch?.cancel()
        resolveTask?.cancel()
        query = "" // didSet clears suggestions / error via queryDidChange()
    }

    // MARK: - Internal (exercised directly by tests)

    /// The debounced-search body: validate, call the service, publish results.
    func runSearch(_ rawQuery: String) async {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= Self.minimumQueryLength else {
            suggestions = []
            isSearching = false
            errorText = nil
            return
        }

        isSearching = true
        errorText = nil
        do {
            let results = try await service.suggestions(matching: query, near: origin)
            guard !Task.isCancelled else { return }
            suggestions = results
        } catch is CancellationError {
            return
        } catch {
            suggestions = []
            errorText = Self.searchFailureText
        }
        isSearching = false
    }

    func resolve(_ suggestion: PlaceSuggestion) async {
        pendingSearch?.cancel()
        isSearching = true
        errorText = nil
        do {
            let destination = try await service.details(for: suggestion.placeID)
            guard !Task.isCancelled else { return }
            onDestinationChosen(destination)
            clearFieldState()
        } catch is CancellationError {
            return
        } catch {
            errorText = Self.resolveFailureText
            isSearching = false
        }
    }

    // MARK: - Private

    private func queryDidChange() {
        pendingSearch?.cancel()
        let raw = query
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength else {
            suggestions = []
            isSearching = false
            errorText = nil
            return
        }
        pendingSearch = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }
            await self.runSearch(raw)
        }
    }

    private func clearFieldState() {
        pendingSearch?.cancel()
        suggestions = []
        isSearching = false
        errorText = nil
        // Set the backing field without re-triggering a search.
        if !query.isEmpty { query = "" }
    }
}
