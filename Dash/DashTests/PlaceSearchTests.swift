//
//  PlaceSearchTests.swift
//  DashTests
//
//  SDK-independent destination-search logic: the debounce / suggestion / resolve
//  orchestration in `PlaceSearchViewModel`, and `DestinationStore`. Google's
//  Places SDK is not exercised here — a stub `PlaceSearchService` stands in.
//

import Foundation
import Testing
@testable import Dash

// MARK: - Stub service

@MainActor
private final class StubPlaceSearchService: PlaceSearchService {

    var suggestionsResult: Result<[PlaceSuggestion], Error> = .success([])
    var detailsResult: Result<Destination, Error> = .failure(PlaceSearchError.placeNotFound)

    private(set) var suggestionCalls: [(query: String, origin: MapCoordinate?)] = []
    private(set) var detailCalls: [String] = []

    func suggestions(matching query: String, near origin: MapCoordinate?) async throws -> [PlaceSuggestion] {
        suggestionCalls.append((query, origin))
        return try suggestionsResult.get()
    }

    func details(for placeID: String) async throws -> Destination {
        detailCalls.append(placeID)
        return try detailsResult.get()
    }
}

private func suggestion(_ id: String, _ primary: String = "Place") -> PlaceSuggestion {
    PlaceSuggestion(placeID: id, primaryText: primary, secondaryText: "Bengaluru")
}

private func destination(_ id: String) -> Destination {
    Destination(
        placeID: id,
        name: "Blue Tokai Coffee",
        address: "1st Block, Koramangala",
        coordinate: MapCoordinate(latitude: 12.93, longitude: 77.62)
    )
}

// MARK: - Google suggestion mapping (pure, SDK-free signatures)

@Suite("GooglePlaceSuggestionMapping")
struct GooglePlaceSuggestionMappingTests {

    @Test("Google place types map to a coarse category, most specific first")
    func categoryMapping() {
        #expect(GooglePlaceSearchService.category(for: ["cafe", "food", "point_of_interest"]) == .cafe)
        #expect(GooglePlaceSearchService.category(for: ["restaurant", "food", "establishment"]) == .food)
        #expect(GooglePlaceSearchService.category(for: ["gas_station"]) == .fuel)
        #expect(GooglePlaceSearchService.category(for: ["supermarket", "grocery_or_supermarket"]) == .shopping)
        #expect(GooglePlaceSearchService.category(for: ["lodging"]) == .lodging)
        #expect(GooglePlaceSearchService.category(for: ["airport"]) == .transit)
        #expect(GooglePlaceSearchService.category(for: ["tourist_attraction", "museum"]) == .landmark)
        #expect(GooglePlaceSearchService.category(for: ["locality", "political"]) == .geographic)
        #expect(GooglePlaceSearchService.category(for: []) == .place)
        #expect(GooglePlaceSearchService.category(for: ["establishment", "point_of_interest"]) == .place)
    }

    @Test("secondary context is recovered from the full text when the name prefixes it")
    func contextStripping() {
        #expect(
            GooglePlaceSearchService.context(strippingPrefix: "Starbucks", from: "Starbucks, MG Road, Bengaluru")
                == "MG Road, Bengaluru"
        )
        // No prefix match → the full text is kept as-is.
        #expect(
            GooglePlaceSearchService.context(strippingPrefix: "Foo", from: "Bar Baz, Indiranagar") == "Bar Baz, Indiranagar"
        )
        // Name equals the full text → nothing left over.
        #expect(GooglePlaceSearchService.context(strippingPrefix: "Cubbon Park", from: "Cubbon Park") == nil)
    }

    @Test("the SDK's own secondary line passes straight through to PlaceSuggestion")
    func secondaryTextPassesThrough() {
        // The exact shape seen on device: SDK gives all three lines.
        #expect(
            GooglePlaceSearchService.secondaryText(
                primary: "Starbucks - Sector 7",
                secondary: "Madhya Marg, Sector 7-C, Sector 7, Chandigarh, India",
                full: "Starbucks - Sector 7, Madhya Marg, Sector 7-C, Sector 7, Chandigarh, India"
            ) == "Madhya Marg, Sector 7-C, Sector 7, Chandigarh, India"
        )
        // Blank SDK secondary → recover the tail of the full text.
        #expect(
            GooglePlaceSearchService.secondaryText(
                primary: "Starbucks",
                secondary: "  ",
                full: "Starbucks, VR Punjab, Kharar"
            ) == "VR Punjab, Kharar"
        )
        // Nothing usable anywhere → nil (the row simply omits the line).
        #expect(
            GooglePlaceSearchService.secondaryText(primary: "Starbucks", secondary: nil, full: "Starbucks") == nil
        )
    }
}

// MARK: - DestinationStore

@MainActor
@Suite("DestinationStore")
struct DestinationStoreTests {

    @Test("starts empty")
    func startsEmpty() {
        let store = DestinationStore()
        #expect(store.destination == nil)
        #expect(store.hasDestination == false)
    }

    @Test("select then clear")
    func selectThenClear() {
        let store = DestinationStore()
        store.select(destination("abc"))
        #expect(store.destination?.placeID == "abc")
        #expect(store.hasDestination)

        store.clear()
        #expect(store.destination == nil)
    }
}

// MARK: - PlaceSearchViewModel

@MainActor
@Suite("PlaceSearchViewModel")
struct PlaceSearchViewModelTests {

    private func makeViewModel(_ service: StubPlaceSearchService) -> PlaceSearchViewModel {
        PlaceSearchViewModel(service: service, debounce: .zero)
    }

    @Test("a query shorter than the minimum does not hit the service")
    func shortQueryIsIgnored() async {
        let service = StubPlaceSearchService()
        let vm = makeViewModel(service)

        await vm.runSearch("a")

        #expect(service.suggestionCalls.isEmpty)
        #expect(vm.suggestions.isEmpty)
        #expect(vm.isSearching == false)
    }

    @Test("a valid query publishes the service's suggestions")
    func validQueryPublishesResults() async {
        let service = StubPlaceSearchService()
        service.suggestionsResult = .success([suggestion("1"), suggestion("2")])
        let vm = makeViewModel(service)

        await vm.runSearch("blue tokai")

        #expect(service.suggestionCalls.map(\.query) == ["blue tokai"])
        #expect(vm.suggestions.map(\.placeID) == ["1", "2"])
        #expect(vm.isSearching == false)
        #expect(vm.errorText == nil)
    }

    @Test("the current origin is passed to the service for biasing")
    func originIsForwarded() async {
        let service = StubPlaceSearchService()
        let vm = makeViewModel(service)
        vm.origin = MapCoordinate(latitude: 12.9, longitude: 77.6)

        await vm.runSearch("cafe")

        #expect(service.suggestionCalls.first?.origin == MapCoordinate(latitude: 12.9, longitude: 77.6))
    }

    @Test("a service failure clears results and shows an error")
    func failureShowsError() async {
        let service = StubPlaceSearchService()
        service.suggestionsResult = .failure(PlaceSearchError.unavailable)
        let vm = makeViewModel(service)

        await vm.runSearch("anything")

        #expect(vm.suggestions.isEmpty)
        #expect(vm.errorText == PlaceSearchViewModel.searchFailureText)
        #expect(vm.isSearching == false)
    }

    @Test("editing the query runs a debounced search")
    func debouncedQueryRuns() async {
        let service = StubPlaceSearchService()
        service.suggestionsResult = .success([suggestion("x")])
        let vm = makeViewModel(service)

        vm.query = "koramangala"
        await vm.pendingSearch?.value

        #expect(vm.suggestions.map(\.placeID) == ["x"])
    }

    @Test("clearing the query below the minimum wipes results without a call")
    func clearingQueryWipesResults() async {
        let service = StubPlaceSearchService()
        service.suggestionsResult = .success([suggestion("x")])
        let vm = makeViewModel(service)

        vm.query = "airport"
        await vm.pendingSearch?.value
        #expect(vm.suggestions.isEmpty == false)

        vm.query = ""
        #expect(vm.suggestions.isEmpty)
        #expect(vm.errorText == nil)
    }

    @Test("choosing a suggestion resolves it, hands out the destination, and resets the field")
    func chooseResolvesAndResets() async {
        let service = StubPlaceSearchService()
        service.detailsResult = .success(destination("dest-1"))
        let vm = makeViewModel(service)
        vm.query = "blue"

        var chosen: Destination?
        vm.onDestinationChosen = { chosen = $0 }

        await vm.resolve(suggestion("dest-1"))

        #expect(service.detailCalls == ["dest-1"])
        #expect(chosen?.placeID == "dest-1")
        #expect(vm.query == "")
        #expect(vm.suggestions.isEmpty)
        #expect(vm.errorText == nil)
    }

    @Test("a failed resolve surfaces an error and hands out nothing")
    func failedResolveShowsError() async {
        let service = StubPlaceSearchService()
        service.detailsResult = .failure(PlaceSearchError.placeNotFound)
        let vm = makeViewModel(service)

        var chosen: Destination?
        vm.onDestinationChosen = { chosen = $0 }

        await vm.resolve(suggestion("dest-1"))

        #expect(chosen == nil)
        #expect(vm.errorText == PlaceSearchViewModel.resolveFailureText)
    }

    @Test("reset clears the field and results")
    func resetClears() async {
        let service = StubPlaceSearchService()
        service.suggestionsResult = .success([suggestion("x")])
        let vm = makeViewModel(service)

        vm.query = "cafe"
        await vm.pendingSearch?.value
        vm.reset()

        #expect(vm.query == "")
        #expect(vm.suggestions.isEmpty)
    }
}
