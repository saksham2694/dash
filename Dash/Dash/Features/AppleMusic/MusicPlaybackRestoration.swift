//
//  MusicPlaybackRestoration.swift
//  Dash — Apple Music feature
//
//  Persists enough about the last-played song to restore it across a
//  relaunch (M9.0 §"Last played / relaunch"). MusicKit itself doesn't
//  persist a queue across process termination, so this is the one piece of
//  local state the feature keeps — just an id + a position, not a second
//  playback engine.
//
//  Platform restriction (reported, not worked around): iOS does not let an
//  app auto-start audio playback on a cold launch without a user gesture —
//  there is no supported MusicKit/AVFoundation API to bypass this. The
//  strongest supported behaviour, and what `MusicPlayerViewModel` actually
//  does, is: restore the queue to the last song and seek to the last
//  position, so Now Playing shows the right song and Play resumes exactly
//  where it left off — the driver still has to tap Play once.
//

import Foundation
import MusicKit

nonisolated struct MusicPlaybackRecord: Codable, Equatable, Sendable {
    var songID: String
    var title: String
    var artistName: String
    var position: TimeInterval
    var savedAt: Date
}

@MainActor
enum MusicPlaybackRestoration {

    private static let storageKey = "appleMusic.lastPlayed.v1"

    static func save(_ record: MusicPlaybackRecord, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> MusicPlaybackRecord? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(MusicPlaybackRecord.self, from: data)
    }
}
