//
//  MusicPlayerViewModel.swift
//  Dash — Apple Music feature
//
//  THE shared Apple Music playback/state layer (M9.0 §"Core music
//  functionality": "one shared Apple Music playback/state layer for the
//  entire feature... the app, compact widget, medium widget, and large
//  widget must all operate on the SAME playback state/player"). Owned once
//  by `AppleMusicFeature` and handed to every Music view — full-screen and
//  every widget size — as the same instance.
//
//  Wraps `ApplicationMusicPlayer.shared` directly (the concrete player, per
//  instruction — no protocol here, unlike the feature's other MusicKit
//  service boundaries). `ObservableObject`, not a `TimelineView`-driven
//  struct like `SpeedometerViewModel`: playback events are irregular, and a
//  short ticker (below) is enough to keep the progress bar smooth without a
//  30 Hz redraw loop.
//
//  M9.0 refinement #1 — track-change sync bug: `.state`/`.queue` fire
//  `objectWillChange` synchronously *before* their own properties actually
//  update (standard `ObservableObject` convention: "will" change, not "did").
//  Reading `player.queue.currentEntry` immediately inside that notification's
//  callback — the original code did — can therefore observe the OUTGOING
//  entry, not the incoming one. The fix is `syncFromPlayer()` deferred by one
//  runloop turn (`Task { @MainActor in }`) rather than called synchronously
//  inside the `sink`, so it always reads the settled state. The ticker below
//  also runs the SAME full sync every tick, not just `playbackTime`.
//
//  M9.0 refinement #2 — duration was still 0:00 after the above fix, on a
//  real device. Root cause: `ApplicationMusicPlayer.Queue.Entry.item` is
//  documented as, and in practice is, a MINIMAL representation of the
//  playing item — that's exactly why `Entry` exposes `title` / `subtitle` /
//  `artwork` directly as convenience properties, rather than requiring
//  callers to go through `.item`. Extended attributes like `Song.duration`
//  are not reliably present on `entry.item` at runtime, regardless of sync
//  timing — no amount of re-reading it sooner fixes a value that was never
//  populated. `duration` (below) now prefers `entry.item`'s own value when
//  MusicKit does supply it, and otherwise falls back to `knownDurations` — a
//  small cache of REAL durations taken from the actual `Song`/`Track`
//  objects this view model was handed to queue in the first place (genuine
//  catalog/library data, matched back to the live queue by `MusicItemID`,
//  which unlike `duration` IS reliably present on `entry.item`).
//

import Combine
import Foundation
import MusicKit

@MainActor
final class MusicPlayerViewModel: ObservableObject {

    typealias Entry = ApplicationMusicPlayer.Queue.Entry

    @Published private(set) var playbackStatus: MusicPlayer.PlaybackStatus = .stopped
    @Published private(set) var currentEntry: Entry?
    @Published private(set) var playbackTime: TimeInterval = 0

    private let player = ApplicationMusicPlayer.shared
    private let catalogSearch: any MusicCatalogSearchService
    /// Injectable purely for testing the restore/persist logic in isolation
    /// (an ephemeral suite instead of the real `UserDefaults.standard`) —
    /// production always uses the default.
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private var tickerTask: Task<Void, Never>?
    private var lastPersistedPosition: TimeInterval = -1

    /// Real durations for songs/tracks this view model has actually queued,
    /// keyed by their catalog `MusicItemID` — see this file's header
    /// ("refinement #2") for why this exists at all. Populated by
    /// `remember(_:)` every time `play(_:startingAt:)` is called, so it
    /// covers Next/Previous through the same queue for free (no per-skip
    /// update needed).
    private var knownDurations: [String: TimeInterval] = [:]

    var isPlaying: Bool { playbackStatus == .playing }

    /// The current item's id, the one thing `entry.item` reliably carries
    /// even when its extended attributes don't — every `MusicItem` has an
    /// `id`. Used both for the duration fallback below and for persistence.
    private var currentItemID: MusicItemID? { currentEntry?.item?.id }

    /// The current song's duration (§3: "duration must be populated from
    /// the current MusicKit playback/now-playing state"). Tries MusicKit's
    /// own value on the live entry first; falls back to `knownDurations`
    /// when that's not present (the common case in practice — see header).
    /// Always sourced fresh from `currentEntry`/`knownDurations` when read,
    /// never cached on its own, so a track change is reflected the instant
    /// `currentEntry` itself is.
    var duration: TimeInterval? {
        let itemDuration: TimeInterval?
        if let song = currentEntry?.item as? Song {
            itemDuration = song.duration
        } else if let track = currentEntry?.item as? Track {
            itemDuration = track.duration
        } else {
            itemDuration = nil
        }
        let cached = currentItemID.flatMap { knownDurations[$0.rawValue] }
        return Self.resolvedDuration(itemDuration: itemDuration, cachedDuration: cached)
    }

    /// The actual duration-selection rule, pulled out as a pure function so
    /// it's unit-testable without a real `Song`/`Track` (neither has a public
    /// initializer — see this file's header, "refinement #2"): prefer the
    /// live entry's own duration when MusicKit actually supplied one, else
    /// fall back to the cached value from when this item was queued.
    nonisolated static func resolvedDuration(itemDuration: TimeInterval?, cachedDuration: TimeInterval?) -> TimeInterval? {
        itemDuration ?? cachedDuration
    }

    init(catalogSearch: any MusicCatalogSearchService, defaults: UserDefaults = .standard) {
        self.catalogSearch = catalogSearch
        self.defaults = defaults
        observePlayer()
        startTicker()
        Task { await restoreLastPlayedIfAvailable() }
    }

    deinit {
        tickerTask?.cancel()
    }

    // MARK: - Observing the shared player

    /// `.state` and `.queue` are themselves `ObservableObject`s — this
    /// mirrors their changes into this view model's own `@Published`
    /// properties, the pattern Apple's own MusicKit sample code uses.
    ///
    /// The sync is deferred one runloop turn past each notification (see
    /// this file's header) rather than run synchronously inside the `sink` —
    /// that one change is the actual fix for stale title/artist/artwork
    /// after Next/Previous.
    private func observePlayer() {
        player.state.objectWillChange
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        player.queue.objectWillChange
            .sink { [weak self] _ in self?.scheduleSync() }
            .store(in: &cancellables)

        syncFromPlayer()
    }

    /// Defers to the next runloop turn so the property that triggered
    /// `objectWillChange` has actually finished mutating by the time we read
    /// it — see this file's header comment.
    private func scheduleSync() {
        Task { @MainActor [weak self] in
            self?.syncFromPlayer()
        }
    }

    /// The one place every observable field is read together, so metadata,
    /// artwork, duration, playback state and position always update as one
    /// consistent snapshot (§2: "must all update together") — never patched
    /// individually.
    private func syncFromPlayer() {
        playbackStatus = player.state.playbackStatus
        currentEntry = player.queue.currentEntry
        playbackTime = player.playbackTime
        persistIfNeeded()
    }

    /// A light periodic full re-sync — not just `playbackTime` — so the
    /// progress bar advances smoothly between notifications AND self-heals
    /// metadata/duration within one tick even in the (now unlikely, but not
    /// impossible) case a given `objectWillChange` is missed. This is the
    /// existing playback-observation mechanism the view model already had;
    /// §4/§5 asked not to introduce a second one, so this tick is reused
    /// rather than adding another timer.
    private func startTicker() {
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.syncFromPlayer()
            }
        }
    }

    // MARK: - Controls (M9.0 §"Core music functionality")

    func play(_ songs: [Song], startingAt song: Song? = nil) async {
        remember(songs)
        player.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: song)
        await startPlayback()
    }

    func play(_ tracks: [Track], startingAt track: Track? = nil) async {
        remember(tracks)
        player.queue = ApplicationMusicPlayer.Queue(for: tracks, startingAt: track)
        await startPlayback()
    }

    /// Records real durations for `knownDurations`'s fallback — see this
    /// file's header ("refinement #2").
    private func remember(_ songs: [Song]) {
        for song in songs {
            if let duration = song.duration { knownDurations[song.id.rawValue] = duration }
        }
    }

    private func remember(_ tracks: [Track]) {
        for track in tracks {
            if let duration = track.duration { knownDurations[track.id.rawValue] = duration }
        }
    }

    func togglePlayPause() async {
        if isPlaying {
            player.pause()
        } else {
            await startPlayback()
        }
    }

    func skipToNext() async {
        try? await player.skipToNextEntry()
    }

    func skipToPrevious() async {
        try? await player.skipToPreviousEntry()
    }

    func seek(to time: TimeInterval) {
        player.playbackTime = max(0, time)
        playbackTime = player.playbackTime
        persistIfNeeded(force: true)
    }

    private func startPlayback() async {
        // A failure here (no subscription, no network, …) just leaves
        // `playbackStatus` non-`.playing` — the Now Playing / widget views
        // already handle that as their normal "nothing playing" state
        // rather than needing a dedicated error path for this first pass.
        try? await player.play()
        syncFromPlayer()
    }

    // MARK: - Persistence (M9.0 §"Last played / relaunch")

    /// Saves roughly every 3 seconds of playback progress, plus every
    /// explicit seek — enough to restore the right song and a close-enough
    /// position without writing to disk on every tick.
    private func persistIfNeeded(force: Bool = false) {
        // Only needs `entry.item?.id` — not a successful `Song` cast — for
        // the same reason `duration` doesn't rely on one either.
        guard let entry = currentEntry, let id = currentItemID else { return }
        guard force || abs(playbackTime - lastPersistedPosition) >= 3 else { return }
        lastPersistedPosition = playbackTime
        MusicPlaybackRestoration.save(MusicPlaybackRecord(
            songID: id.rawValue,
            title: entry.title,
            artistName: entry.subtitle ?? "",
            position: playbackTime,
            savedAt: Date()
        ), to: defaults)
    }

    /// Restores the queue + position from the last launch into the SAME
    /// `ApplicationMusicPlayer.shared` this view model already wraps — no
    /// second player instance.
    ///
    /// Order matters: the queue is set and seeked FIRST, and `syncFromPlayer()`
    /// runs immediately after so the restored song is visible in Now
    /// Playing / every widget right away, even if the autoplay attempt right
    /// after this either doesn't run or is rejected by the platform.
    ///
    /// The autoplay attempt is real, not skipped: `player.play()` is
    /// actually called once. iOS's restriction on starting audio without a
    /// user gesture applies most strictly to passive contexts (e.g. a web
    /// page); a native app's own foreground-launch code calling its
    /// player's `play()` can succeed in some launch contexts and be silently
    /// rejected in others, and this repo has no way to exercise every real
    /// launch context to know which. So: try once, never retry, never
    /// surface an error to the user — a rejection just leaves the restored
    /// song paused at the restored position, which is what "if autoplay is
    /// restricted, leave the restored song paused at the restored position"
    /// asks for either way.
    private func restoreLastPlayedIfAvailable() async {
        guard currentEntry == nil, let record = MusicPlaybackRestoration.load(from: defaults) else { return }
        do {
            guard let song = try await catalogSearch.song(withID: MusicItemID(record.songID)) else { return }
            remember([song])
            player.queue = ApplicationMusicPlayer.Queue(for: [song])
            try? await player.prepareToPlay()
            player.playbackTime = record.position
            syncFromPlayer()

            // One real, best-effort autoplay attempt — see doc comment above.
            try? await player.play()
            if !isPlaying {
                // Rejected (or genuinely failed) — restore the exact saved
                // position again, since a rejected `play()` can leave
                // `playbackTime` at 0 rather than where we just set it.
                player.playbackTime = record.position
            }
            syncFromPlayer()
        } catch {
            // No connectivity / song no longer in the catalog — nothing to
            // restore; the player just starts in its normal empty state.
        }
    }
}
