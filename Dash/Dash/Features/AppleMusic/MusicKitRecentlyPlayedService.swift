//
//  MusicKitRecentlyPlayedService.swift
//  Dash — Apple Music feature
//
//  The production `MusicRecentlyPlayedService` — `MusicRecentlyPlayedRequest<Song>`.
//  Reflects the person's actual Apple Music listening history (kept by Apple,
//  across all their devices/apps) — Dash doesn't maintain its own separate
//  "recently played" log.
//

import Foundation
import MusicKit

struct MusicKitRecentlyPlayedService: MusicRecentlyPlayedService {

    func recentlyPlayedSongs(limit: Int = 25) async throws -> MusicItemCollection<Song> {
        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = limit
        return try await request.response().items
    }
}
