//
//  SettingsRootView.swift
//  Dash — Settings feature
//
//  The Settings home screen (M8.3 §2): three Apple-style grouped sections —
//  General, Wallpaper, and Apps — each with its own section header, a plain
//  `NavigationStack` + `.insetGrouped` `List`, so section headers, row height,
//  separators, disclosure chevrons and system background colour all come from
//  native SwiftUI/UIKit rather than being hand-built.
//
//  `.preferredColorScheme(nil)` at the root is deliberate: `DashboardShell`
//  forces `.dark` for the whole automotive shell, but Settings is meant to
//  feel like a conventional Apple app (M8.3 §6) — `nil` clears that ancestor
//  override for this subtree, so Settings follows the SYSTEM's actual
//  light/dark setting like any other app. `.tint(.blue)` keeps its
//  checkmarks/links the familiar Settings blue rather than inheriting Dash's
//  automotive accent colour.
//
//  Feature-agnostic (M8.3 §8): the Apps section is built entirely from
//  `FeatureRegistry.manifests` — no feature is named here. Settings excludes
//  itself from that list (tapping "Settings" inside "Apps" would just reopen
//  this same screen — a pointless loop with zero value).
//

import SwiftUI

struct SettingsRootView: View {

    @EnvironmentObject private var registry: FeatureRegistry

    /// Every registered app except Settings itself. Pure + tested.
    static func apps(from manifests: [FeatureManifest]) -> [FeatureManifest] {
        manifests.filter { $0.id != SettingsFeature.id }
    }

    private var apps: [FeatureManifest] { Self.apps(from: registry.manifests) }

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    NavigationLink {
                        SettingsGeneralView()
                    } label: {
                        SettingsRow(symbolName: "gearshape.fill", tint: .graphite, title: "General")
                    }
                }

                Section("Wallpaper") {
                    NavigationLink {
                        SettingsWallpaperView()
                    } label: {
                        SettingsRow(symbolName: "photo.fill", tint: .indigo, title: "Wallpaper")
                    }
                }

                Section("Apps") {
                    ForEach(apps) { manifest in
                        NavigationLink {
                            SettingsAppDetailView(manifest: manifest)
                        } label: {
                            SettingsRow(manifest: manifest)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
        .tint(.blue)
        .preferredColorScheme(nil)
    }
}

#if DEBUG
#Preview {
    SettingsRootView()
        .environmentObject(FeatureRegistry.makeDefault())
        .environmentObject(WallpaperStore())
        .environmentObject(SpeedUnitStore())
        .environmentObject(MapAppearanceStore())
}
#endif
