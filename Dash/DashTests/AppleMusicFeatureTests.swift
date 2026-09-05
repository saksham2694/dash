//
//  AppleMusicFeatureTests.swift
//  DashTests
//
//  M9.0 — targeted tests for the Apple Music feature's pure logic and
//  protocol-fakeable view-model behaviour, per instruction ("do NOT spend
//  excessive time on exhaustive testing yet"):
//    • `MusicFormatting` — time text, progress.
//    • `MusicAccessStatus` — the `MusicAuthorization.Status` mapping.
//    • `MusicAccessViewModel` — authorization/subscription state transitions
//      against fake services.
//    • `MusicPlaybackRestoration` — the last-played persistence round-trip.
//    • `MusicFavoritesStore` — the id-based local favorite bookkeeping.
//    • `MusicLibraryCategory` — the pure display metadata.
//    • `AppleMusicFeature` — stable id, all four sizes supported, real
//      registration.
//    • `MusicPlayerViewModel`'s restoration CONTROL FLOW (no saved record;
//      an unresolvable saved record) against an injectable `UserDefaults` —
//      added in the M9.0 playback/state-sync refinement pass.
//
//  MusicKit's own model types (`Song`, `Album`, …) have no public
//  initializer, so anything that needs a real one (search results, the
//  Song-taking favorite convenience methods, and `MusicPlayerViewModel`'s
//  actual sync/playback against the real `ApplicationMusicPlayer.shared`)
//  isn't unit-testable in this environment — noted rather than faked around.
//

import CoreGraphics
import Foundation
import MusicKit
import Testing
@testable import Dash

// MARK: - Fixtures

@MainActor
private final class FakeAuthorizationService: MusicAuthorizationService, @unchecked Sendable {
    var currentStatus: MusicAccessStatus
    var statusAfterRequest: MusicAccessStatus

    init(status: MusicAccessStatus, statusAfterRequest: MusicAccessStatus? = nil) {
        self.currentStatus = status
        self.statusAfterRequest = statusAfterRequest ?? status
    }

    func requestAccess() async -> MusicAccessStatus {
        currentStatus = statusAfterRequest
        return currentStatus
    }
}

@MainActor
private final class FakeSubscriptionService: MusicSubscriptionService, @unchecked Sendable {
    var status: MusicSubscriptionStatus
    init(status: MusicSubscriptionStatus) { self.status = status }
    func currentStatus() async -> MusicSubscriptionStatus { status }
}

private actor FakeFavoritesService: MusicFavoritesService {
    private var serverFavorites: Set<String> = []
    private(set) var setFavoriteCallCount = 0

    func isFavorite(songID: MusicItemID) async -> Bool {
        serverFavorites.contains(songID.rawValue)
    }

    func setFavorite(songID: MusicItemID, isFavorite: Bool) async throws {
        setFavoriteCallCount += 1
        if isFavorite {
            serverFavorites.insert(songID.rawValue)
        } else {
            serverFavorites.remove(songID.rawValue)
        }
    }
}

/// A catalog search service that never actually finds a song — `Song` has
/// no public initializer, so no fake can return a real one. Good enough to
/// exercise `MusicPlayerViewModel`'s restoration control flow (it must
/// handle "song not found" gracefully) without needing a real one.
private struct NoResultsCatalogSearchService: MusicCatalogSearchService {
    func search(term: String, limit: Int) async throws -> MusicCatalogSearchResults { MusicCatalogSearchResults() }
    func song(withID id: MusicItemID) async throws -> Song? { nil }
    func songs(withIDs ids: [MusicItemID]) async throws -> MusicItemCollection<Song> { [] }
}

// MARK: - MusicFormatting

@Suite("MusicFormatting")
struct MusicFormattingTests {

    @Test("time text formats as m:ss")
    func timeTextFormatting() {
        #expect(MusicFormatting.timeText(0) == "0:00")
        #expect(MusicFormatting.timeText(45) == "0:45")
        #expect(MusicFormatting.timeText(65) == "1:05")
        #expect(MusicFormatting.timeText(3725) == "62:05")
    }

    @Test("time text never goes negative or non-finite")
    func timeTextIsSafe() {
        #expect(MusicFormatting.timeText(-5) == "0:00")
        #expect(MusicFormatting.timeText(.nan) == "0:00")
        #expect(MusicFormatting.timeText(.infinity) == "0:00")
    }

    @Test("progress is 0 without a known duration")
    func progressWithoutDuration() {
        #expect(MusicFormatting.progress(time: 30, duration: nil) == 0)
        #expect(MusicFormatting.progress(time: 30, duration: 0) == 0)
    }

    @Test("progress is clamped to 0...1")
    func progressClamped() {
        #expect(MusicFormatting.progress(time: 0, duration: 100) == 0)
        #expect(MusicFormatting.progress(time: 50, duration: 100) == 0.5)
        #expect(MusicFormatting.progress(time: 100, duration: 100) == 1)
        #expect(MusicFormatting.progress(time: 150, duration: 100) == 1)
        #expect(MusicFormatting.progress(time: -10, duration: 100) == 0)
    }
}

// MARK: - MusicAccessStatus

@Suite("MusicAccessStatus")
struct MusicAccessStatusTests {

    @Test("maps every MusicAuthorization.Status case")
    func mapsEveryCase() {
        #expect(MusicAccessStatus(.authorized) == .authorized)
        #expect(MusicAccessStatus(.denied) == .denied)
        #expect(MusicAccessStatus(.restricted) == .restricted)
        #expect(MusicAccessStatus(.notDetermined) == .notDetermined)
    }
}

// MARK: - MusicAccessViewModel

@MainActor
@Suite("MusicAccessViewModel")
struct MusicAccessViewModelTests {

    @Test("starts reflecting the service's current status")
    func startsWithCurrentStatus() {
        let vm = MusicAccessViewModel(
            authService: FakeAuthorizationService(status: .authorized),
            subscriptionService: FakeSubscriptionService(status: .unknown)
        )
        #expect(vm.isAuthorized)
    }

    @Test("requesting access when not determined updates the status")
    func requestsWhenNotDetermined() async {
        let auth = FakeAuthorizationService(status: .notDetermined, statusAfterRequest: .authorized)
        let vm = MusicAccessViewModel(authService: auth, subscriptionService: FakeSubscriptionService(status: .unknown))
        #expect(!vm.isAuthorized)

        await vm.requestAccessIfNeeded()

        #expect(vm.isAuthorized)
    }

    @Test("a denied status is never re-requested into authorized by requestAccessIfNeeded")
    func deniedStaysDenied() async {
        let auth = FakeAuthorizationService(status: .denied, statusAfterRequest: .authorized)
        let vm = MusicAccessViewModel(authService: auth, subscriptionService: FakeSubscriptionService(status: .unknown))

        await vm.requestAccessIfNeeded()

        // Only `.notDetermined` triggers a request — an already-decided
        // `.denied` status must not be silently overwritten.
        #expect(vm.authorizationStatus == .denied)
        #expect(!vm.isAuthorized)
    }

    @Test("subscription status is refreshed once authorized")
    func refreshesSubscriptionWhenAuthorized() async {
        let auth = FakeAuthorizationService(status: .notDetermined, statusAfterRequest: .authorized)
        let subscription = FakeSubscriptionService(status: .init(canPlayCatalogContent: true, canBecomeSubscriber: false))
        let vm = MusicAccessViewModel(authService: auth, subscriptionService: subscription)

        await vm.requestAccessIfNeeded()

        #expect(vm.canPlayCatalogContent)
    }

    @Test("subscription status is not fetched while unauthorized")
    func doesNotRefreshSubscriptionWhenDenied() async {
        let auth = FakeAuthorizationService(status: .denied)
        let subscription = FakeSubscriptionService(status: .init(canPlayCatalogContent: true, canBecomeSubscriber: false))
        let vm = MusicAccessViewModel(authService: auth, subscriptionService: subscription)

        await vm.requestAccessIfNeeded()

        #expect(!vm.canPlayCatalogContent)   // stayed at `.unknown`'s default
    }
}

// MARK: - MusicPlaybackRestoration

@MainActor
@Suite("MusicPlaybackRestoration")
struct MusicPlaybackRestorationTests {

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "music-restore-\(UUID().uuidString)")!
    }

    @Test("nothing to load when nothing was saved")
    func nothingSavedYieldsNil() {
        #expect(MusicPlaybackRestoration.load(from: ephemeralDefaults()) == nil)
    }

    @Test("a saved record round-trips exactly")
    func roundTrips() {
        let defaults = ephemeralDefaults()
        let record = MusicPlaybackRecord(
            songID: "12345",
            title: "A Song",
            artistName: "An Artist",
            position: 42.5,
            savedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        MusicPlaybackRestoration.save(record, to: defaults)
        #expect(MusicPlaybackRestoration.load(from: defaults) == record)
    }

    @Test("saving again overwrites the previous record")
    func savingOverwrites() {
        let defaults = ephemeralDefaults()
        MusicPlaybackRestoration.save(
            MusicPlaybackRecord(songID: "1", title: "First", artistName: "A", position: 0, savedAt: Date()),
            to: defaults
        )
        let second = MusicPlaybackRecord(songID: "2", title: "Second", artistName: "B", position: 10, savedAt: Date())
        MusicPlaybackRestoration.save(second, to: defaults)

        #expect(MusicPlaybackRestoration.load(from: defaults) == second)
    }
}

// MARK: - MusicFavoritesStore (id-based bookkeeping)

@MainActor
@Suite("MusicFavoritesStore")
struct MusicFavoritesStoreTests {

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "music-favorites-\(UUID().uuidString)")!
    }

    @Test("a fresh store has no favorites")
    func freshStoreIsEmpty() {
        let store = MusicFavoritesStore(service: FakeFavoritesService(), defaults: ephemeralDefaults())
        #expect(!store.isFavorite(id: MusicItemID("1")))
        #expect(store.favoriteSongIDs.isEmpty)
    }

    @Test("setting a favorite updates local state immediately")
    func setFavoriteUpdatesLocally() {
        let store = MusicFavoritesStore(service: FakeFavoritesService(), defaults: ephemeralDefaults())
        let id = MusicItemID("42")

        store.setFavorite(id: id, isFavorite: true)

        #expect(store.isFavorite(id: id))
        #expect(store.favoriteSongIDs.contains("42"))
    }

    @Test("unsetting a favorite removes it")
    func unsetFavoriteRemoves() {
        let store = MusicFavoritesStore(service: FakeFavoritesService(), defaults: ephemeralDefaults())
        let id = MusicItemID("42")
        store.setFavorite(id: id, isFavorite: true)

        store.setFavorite(id: id, isFavorite: false)

        #expect(!store.isFavorite(id: id))
    }

    @Test("a favorite persists across store instances")
    func persistsAcrossInstances() {
        let defaults = ephemeralDefaults()
        let id = MusicItemID("99")
        let first = MusicFavoritesStore(service: FakeFavoritesService(), defaults: defaults)
        first.setFavorite(id: id, isFavorite: true)

        let reopened = MusicFavoritesStore(service: FakeFavoritesService(), defaults: defaults)
        #expect(reopened.isFavorite(id: id))
    }
}

// MARK: - MusicLibraryCategory

@Suite("MusicLibraryCategory")
struct MusicLibraryCategoryTests {

    @Test("every category has a non-empty title and symbol")
    func everyCategoryHasDisplayMetadata() {
        for category in MusicLibraryCategory.allCases {
            #expect(!category.title.isEmpty)
            #expect(!category.symbolName.isEmpty)
        }
    }

    @Test("covers exactly the four required categories")
    func fourCategories() {
        #expect(Set(MusicLibraryCategory.allCases) == [.songs, .albums, .artists, .playlists])
    }
}

// MARK: - AppleMusicFeature

@MainActor
@Suite("AppleMusicFeature")
struct AppleMusicFeatureTests {

    @Test("keeps the stable id the retired placeholder used")
    func stableID() {
        #expect(AppleMusicFeature.id == "music")
    }

    @Test("supports all four sizes — unlike Speedometer/Weather")
    func supportsAllSizes() {
        let manifest = AppleMusicFeature().manifest
        #expect(manifest.supportedSizes == [.compact, .medium, .large, .full])
        #expect(manifest.supportedWidgetSizes == [.compact, .medium, .large])
    }

    @Test("is registered in the default registry as a real feature")
    func registeredAsReal() {
        let registry = FeatureRegistry.makeDefault()
        #expect(registry.feature("music") as? AppleMusicFeature != nil)
    }
}

// MARK: - MusicPlayerViewModel (restoration control flow)
//
// `MusicPlayerViewModel` wraps the real `ApplicationMusicPlayer.shared`
// directly (no protocol, per the original M9.0 instruction), so its actual
// playback/sync integration isn't independently unit-testable here. What IS
// testable, and matters most for the "last played / relaunch" behaviour,
// is the restoration control flow around that — gated by an injectable
// `UserDefaults` so this never touches the real `.standard` domain.

// MARK: - MusicPlayerViewModel (duration fallback rule)
//
// The targeted fix's actual selection rule ("refinement #2" in
// `MusicPlayerViewModel`'s header): prefer the live queue entry's own
// duration when MusicKit supplied one, else fall back to a cached duration
// captured when the item was queued. Neither `Song` nor `Track` has a public
// initializer, so this is exercised as the plain values the rule actually
// switches on, not through real MusicKit objects.

@Suite("MusicPlayerViewModel duration fallback")
struct MusicPlayerViewModelDurationTests {

    @Test("prefers the live entry's own duration when MusicKit supplies one")
    func prefersLiveDuration() {
        #expect(MusicPlayerViewModel.resolvedDuration(itemDuration: 217, cachedDuration: 9999) == 217)
    }

    @Test("falls back to the cached duration when the entry has none")
    func fallsBackToCache() {
        #expect(MusicPlayerViewModel.resolvedDuration(itemDuration: nil, cachedDuration: 183) == 183)
    }

    @Test("is nil when neither source has a duration")
    func nilWhenNeitherKnown() {
        #expect(MusicPlayerViewModel.resolvedDuration(itemDuration: nil, cachedDuration: nil) == nil)
    }
}

@MainActor
@Suite("MusicPlayerViewModel restoration")
struct MusicPlayerViewModelRestorationTests {

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "music-player-\(UUID().uuidString)")!
    }

    @Test("with no saved record, restoration is a no-op — no crash, nothing to show")
    func noSavedRecordIsNoOp() async {
        let defaults = ephemeralDefaults()
        let viewModel = MusicPlayerViewModel(catalogSearch: NoResultsCatalogSearchService(), defaults: defaults)

        // Restoration runs in a detached `Task` from `init`; give it a beat
        // to finish its (here, immediate) early return.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.currentEntry == nil)
        #expect(viewModel.playbackStatus == .stopped)
        #expect(viewModel.duration == nil)
        #expect(!viewModel.isPlaying)
    }

    @Test("a saved record for a song the catalog lookup can't find degrades gracefully")
    func unresolvableRecordDoesNotCrash() async {
        let defaults = ephemeralDefaults()
        MusicPlaybackRestoration.save(
            MusicPlaybackRecord(songID: "not-a-real-id", title: "Ghost", artistName: "Nobody", position: 30, savedAt: Date()),
            to: defaults
        )

        let viewModel = MusicPlayerViewModel(catalogSearch: NoResultsCatalogSearchService(), defaults: defaults)
        try? await Task.sleep(for: .milliseconds(50))

        // The service returns `nil` for the lookup — restoration should give
        // up cleanly rather than crash or leave the view model in a broken
        // state.
        #expect(viewModel.currentEntry == nil)
        #expect(!viewModel.isPlaying)
    }
}

// MARK: - MusicNowPlayingView swipe-to-dismiss (M9.0 final interaction cleanup)

@Suite("MusicNowPlayingView.isDismissSwipe")
struct MusicNowPlayingViewDismissSwipeTests {

    @Test("a clearly downward swipe past the threshold dismisses")
    func downwardSwipeDismisses() {
        #expect(MusicNowPlayingView.isDismissSwipe(translation: CGSize(width: 4, height: 150)))
    }

    @Test("a short downward movement under the threshold does not dismiss")
    func shortSwipeDoesNotDismiss() {
        #expect(!MusicNowPlayingView.isDismissSwipe(translation: CGSize(width: 0, height: 40)))
    }

    @Test("an upward swipe never dismisses")
    func upwardSwipeDoesNotDismiss() {
        #expect(!MusicNowPlayingView.isDismissSwipe(translation: CGSize(width: 0, height: -150)))
    }

    @Test("a mostly-horizontal drag (seeking, the volume slider) does not dismiss")
    func horizontalDragDoesNotDismiss() {
        #expect(!MusicNowPlayingView.isDismissSwipe(translation: CGSize(width: 200, height: 60)))
    }

    @Test("a near-zero-movement tap never dismisses")
    func tapDoesNotDismiss() {
        #expect(!MusicNowPlayingView.isDismissSwipe(translation: .zero))
    }
}
