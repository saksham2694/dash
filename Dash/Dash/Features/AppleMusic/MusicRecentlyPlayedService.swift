//
//  MusicRecentlyPlayedService.swift
//  Dash — Apple Music feature
//
//  The seam around `MusicRecentlyPlayedRequest` (M9.0 §"Recently played").
//

import Foundation
import MusicKit

protocol MusicRecentlyPlayedService: Sendable {
    func recentlyPlayedSongs(limit: Int) async throws -> MusicItemCollection<Song>
}
