//
//  AppleMusicRootView.swift
//  Dash — Apple Music feature
//
//  The full-screen experience (M9.0 §"Full-screen app", redesigned in the
//  M9.0 UI pass §"Navigation redesign" to feel more like Apple Music itself):
//
//    • Top tabs: Recently Played (default/first) / Search / Library /
//      Favorites — no dedicated Now Playing tab.
//    • A persistent mini player (`MusicMiniPlayerView`) is anchored above the
//      tab bar whenever there's a current song — tapping it (outside its own
//      controls) opens the full Now Playing screen as a cover.
//
//  Final-cleanup note: an earlier pass tried a top-right search TOOLBAR icon
//  instead of a tab (to avoid a fourth tab item) — physical testing showed
//  it repeatedly failed to actually appear, so this reverts to Search as a
//  real tab (the mechanism already known to work), using the same
//  `MusicSearchView` either way. There is deliberately only one search entry
//  point again — no toolbar button alongside it.
//
//  Gated by `MusicAccessViewModel` — shows `MusicAccessGateView` instead
//  until authorized.
//
//  Forces `.dark` — this feature's palette (`MusicTheme`) is deliberately
//  dark-only rather than a fully light/dark-adaptive system, matching how
//  Apple Music's own Now Playing / mini-player stay dark-leaning regardless
//  of system appearance. Never Dash's automotive red accent.
//

import SwiftUI

struct AppleMusicRootView: View {

    let feature: AppleMusicFeature

    @State private var isNowPlayingPresented = false

    var body: some View {
        Group {
            if feature.accessViewModel.isAuthorized {
                TabView {
                    NavigationStack {
                        MusicRecentlyPlayedView(feature: feature)
                    }
                    .tabItem { Label("Recently Played", systemImage: "clock") }

                    NavigationStack {
                        MusicSearchView(feature: feature)
                    }
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }

                    NavigationStack {
                        MusicLibraryView(feature: feature)
                    }
                    .tabItem { Label("Library", systemImage: "music.note.list") }

                    NavigationStack {
                        MusicFavoritesView(feature: feature)
                    }
                    .tabItem { Label("Favorites", systemImage: "heart") }
                }
                .tint(MusicTheme.accent)
                .safeAreaInset(edge: .bottom) {
                    if feature.playerViewModel.currentEntry != nil {
                        MusicMiniPlayerView(playerViewModel: feature.playerViewModel) {
                            isNowPlayingPresented = true
                        }
                    }
                }
            } else {
                MusicAccessGateView(accessViewModel: feature.accessViewModel)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $isNowPlayingPresented) {
            NavigationStack {
                MusicNowPlayingView(playerViewModel: feature.playerViewModel, favoritesStore: feature.favoritesStore)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                isNowPlayingPresented = false
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .task {
            // Only a passive subscription check if already authorized —
            // requesting AUTHORIZATION itself (which pops the system prompt)
            // stays behind the gate's explicit "Connect" button, never
            // fired automatically on appear.
            if feature.accessViewModel.isAuthorized {
                await feature.accessViewModel.refreshSubscription()
            }
        }
    }
}
