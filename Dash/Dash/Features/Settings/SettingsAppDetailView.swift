//
//  SettingsAppDetailView.swift
//  Dash — Settings feature
//
//  The generic per-app settings page (M8.3 §3). Every registered app renders
//  through the SAME placeholder body except Speedometer (Speed Unit) and
//  Google Maps (Map Appearance, M9.1) — explicitly-called-out exceptions, not
//  a per-app switch: Apple Maps, Apple Music and Weather all take the
//  placeholder branch with no feature-specific code of their own. A future
//  feature with real settings gets the same treatment, without any other
//  app's page changing.
//
//  The navigation title is always `manifest.title` — never hardcoded per app.
//
//  Matched by id VALUE, not by referencing the `SpeedometerFeature` type — a
//  feature never references another feature (CLAUDE.md); this is the same
//  stable-string convention `PlaceholderFeature.ID` already uses for ids that
//  belong to a different file.
//

import SwiftUI

/// Speedometer's stable id (matches `SpeedometerFeature.id`, kept as a literal
/// here rather than a reference to that type — see file header). Internal,
/// not `private`, so a test can assert the two stay in sync.
let speedometerFeatureID: FeatureID = "speedometer"

/// Google Maps' stable id (matches `MapFeature.id`, kept as a literal here for
/// the same reason as `speedometerFeatureID` above).
let mapFeatureID: FeatureID = "maps"

struct SettingsAppDetailView: View {

    let manifest: FeatureManifest

    var body: some View {
        Group {
            if manifest.id == speedometerFeatureID {
                SettingsSpeedometerView()
            } else if manifest.id == mapFeatureID {
                SettingsMapsView()
            } else {
                placeholder
            }
        }
        .navigationTitle(manifest.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "No Settings Yet",
            systemImage: manifest.symbolName,
            description: Text("\(manifest.title) has no settings yet.")
        )
    }
}

#if DEBUG
#Preview("Placeholder app") {
    NavigationStack {
        SettingsAppDetailView(manifest: FeatureManifest(
            id: "weather", title: "Weather", symbolName: "cloud.sun.fill",
            supportedSizes: [.full], defaultSize: .full, iconStyle: .pinned(.teal)
        ))
    }
}

#Preview("Speedometer (real setting)") {
    NavigationStack {
        SettingsAppDetailView(manifest: FeatureManifest(
            id: "speedometer", title: "Speedometer", symbolName: "speedometer",
            supportedSizes: [.compact, .medium, .full], defaultSize: .medium,
            iconStyle: .pinned(.orange)
        ))
    }
    .environmentObject(SpeedUnitStore())
}

#Preview("Google Maps (real setting)") {
    NavigationStack {
        SettingsAppDetailView(manifest: FeatureManifest(
            id: "maps", title: "Google Maps", symbolName: "map.fill",
            supportedSizes: [.compact, .medium, .large, .full], defaultSize: .large,
            iconStyle: .pinned(.green)
        ))
    }
    .environmentObject(MapAppearanceStore())
}
#endif
