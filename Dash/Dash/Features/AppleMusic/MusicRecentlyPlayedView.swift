//
//  MusicRecentlyPlayedView.swift
//  Dash — Apple Music feature
//
//  M9.0 §"Recently played" — the person's real Apple Music listening
//  history (`MusicRecentlyPlayedRequest`), not a separate Dash-side log.
//

import SwiftUI

struct MusicRecentlyPlayedView: View {

    let feature: AppleMusicFeature
    @ObservedObject private var recentlyPlayedViewModel: MusicRecentlyPlayedViewModel

    init(feature: AppleMusicFeature) {
        self.feature = feature
        _recentlyPlayedViewModel = ObservedObject(wrappedValue: feature.recentlyPlayedViewModel)
    }

    var body: some View {
        Group {
            if recentlyPlayedViewModel.isLoading && recentlyPlayedViewModel.songs.isEmpty {
                ProgressView().tint(MusicTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = recentlyPlayedViewModel.loadError {
                ContentUnavailableView("Couldn’t Load", systemImage: "clock", description: Text(error))
            } else if recentlyPlayedViewModel.songs.isEmpty {
                ContentUnavailableView(
                    "Nothing Played Yet",
                    systemImage: "clock",
                    description: Text("Songs you play will show up here.")
                )
            } else {
                List {
                    ForEach(recentlyPlayedViewModel.songs) { song in
                        MusicSongRow(song: song, favoritesStore: feature.favoritesStore) {
                            Task { await feature.playerViewModel.play(Array(recentlyPlayedViewModel.songs), startingAt: song) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(MusicTheme.background)
        .navigationTitle("Recently Played")
        .task { await recentlyPlayedViewModel.loadIfNeeded() }
        .refreshable { await recentlyPlayedViewModel.reload() }
    }
}
