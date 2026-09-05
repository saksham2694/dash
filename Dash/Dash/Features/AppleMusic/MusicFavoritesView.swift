//
//  MusicFavoritesView.swift
//  Dash — Apple Music feature
//
//  M9.0 §"Favorites" — the songs favorited from within Dash
//  (`MusicFavoritesStore`, resolved to real songs by `MusicFavoritesViewModel`).
//

import SwiftUI

struct MusicFavoritesView: View {

    let feature: AppleMusicFeature
    @ObservedObject private var favoritesViewModel: MusicFavoritesViewModel

    init(feature: AppleMusicFeature) {
        self.feature = feature
        _favoritesViewModel = ObservedObject(wrappedValue: feature.favoritesViewModel)
    }

    var body: some View {
        Group {
            if favoritesViewModel.songs.isEmpty {
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "heart",
                    description: Text("Tap the heart on any song to favorite it.")
                )
            } else {
                List {
                    ForEach(favoritesViewModel.songs) { song in
                        MusicSongRow(song: song, favoritesStore: feature.favoritesStore) {
                            Task { await feature.playerViewModel.play(Array(favoritesViewModel.songs), startingAt: song) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(MusicTheme.background)
        .navigationTitle("Favorites")
    }
}
