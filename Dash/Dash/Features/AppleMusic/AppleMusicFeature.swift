//
//  AppleMusicFeature.swift
//  Dash — Apple Music feature
//
//  The feature's adapter to the shell and the app-scoped owner of ALL its
//  state — the shared `MusicPlayerViewModel` plus search/library/recently-
//  played/favorites/access. Replaces `PlaceholderFeature.music()` — the id
//  and manifest identity carry over unchanged so persisted Home / dashboard
//  placements keep resolving.
//
//  Self-contained (M9.0 §"Architecture"): this is the ONLY file in the
//  feature that names a `Shell/`-adjacent type (`DashFeature` /
//  `FeatureManifest`). Every MusicKit-backed service has a default,
//  production argument here — the one place they're wired together — and
//  every view (full-screen + every widget size) reads the SAME
//  `playerViewModel` instance, satisfying "the app, compact widget, medium
//  widget, and large widget must all operate on the SAME playback
//  state/player".
//
//  Supports all four sizes (compact/medium/large/full) — unlike Speedometer
//  / Weather, per instruction.
//

import MusicKit
import SwiftUI

@MainActor
final class AppleMusicFeature: DashFeature {

    /// Stable id — matches the retired placeholder so nothing has to migrate.
    static let id: FeatureID = "music"

    let manifest = FeatureManifest(
        id: AppleMusicFeature.id,
        title: "Apple Music",
        symbolName: "music.note",
        supportedSizes: [.compact, .medium, .large, .full],
        defaultSize: .large,
        iconStyle: .pinned(.pink),
        iconAssetName: "app-icon-apple-music"
    )

    /// THE shared playback/state layer — every Music view reads this one
    /// instance.
    let playerViewModel: MusicPlayerViewModel
    let accessViewModel: MusicAccessViewModel
    let searchViewModel: MusicSearchViewModel
    let libraryViewModel: MusicLibraryViewModel
    let recentlyPlayedViewModel: MusicRecentlyPlayedViewModel
    let favoritesStore: MusicFavoritesStore
    let favoritesViewModel: MusicFavoritesViewModel

    private let libraryService: any MusicLibraryService

    init(
        authorizationService: any MusicAuthorizationService = MusicKitAuthorizationService(),
        subscriptionService: any MusicSubscriptionService = MusicKitSubscriptionService(),
        catalogSearchService: any MusicCatalogSearchService = MusicKitCatalogSearchService(),
        libraryService: any MusicLibraryService = MusicKitLibraryService(),
        recentlyPlayedService: any MusicRecentlyPlayedService = MusicKitRecentlyPlayedService(),
        favoritesService: any MusicFavoritesService = MusicKitFavoritesService()
    ) {
        self.libraryService = libraryService
        self.playerViewModel = MusicPlayerViewModel(catalogSearch: catalogSearchService)
        self.accessViewModel = MusicAccessViewModel(
            authService: authorizationService,
            subscriptionService: subscriptionService
        )
        self.searchViewModel = MusicSearchViewModel(service: catalogSearchService)
        self.libraryViewModel = MusicLibraryViewModel(service: libraryService)
        self.recentlyPlayedViewModel = MusicRecentlyPlayedViewModel(service: recentlyPlayedService)
        let favoritesStore = MusicFavoritesStore(service: favoritesService)
        self.favoritesStore = favoritesStore
        self.favoritesViewModel = MusicFavoritesViewModel(favoritesStore: favoritesStore, catalogSearch: catalogSearchService)
    }

    /// Fetches an album's or playlist's tracks — used by the library/search
    /// detail views. Exposed here (rather than a dedicated view model) since
    /// it's a single, stateless call each drill-in view makes for itself.
    func tracks(of album: Album) async throws -> MusicItemCollection<Track> {
        try await libraryService.tracks(of: album)
    }

    func tracks(of playlist: Playlist) async throws -> MusicItemCollection<Track> {
        try await libraryService.tracks(of: playlist)
    }

    private lazy var fullScreenView = AnyView(AppleMusicRootView(feature: self))

    func makeFullScreenView() -> AnyView { fullScreenView }

    private var componentViews: [ComponentSize: AnyView] = [:]

    func makeComponentView(size: ComponentSize) -> AnyView {
        if let cached = componentViews[size] { return cached }
        let view = AnyView(MusicComponentView(feature: self, size: size))
        componentViews[size] = view
        return view
    }
}
