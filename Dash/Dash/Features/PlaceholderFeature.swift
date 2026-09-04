//
//  PlaceholderFeature.swift
//  Dash
//
//  Registered-but-not-yet-implemented features. Apple Maps, Apple Music, Weather
//  and Settings are real Dash features — they belong in the sidebar and the Home
//  launcher with their own identity now, not as dimmed "coming soon" stand-ins.
//  Their runtime isn't built yet, so opening one full-screen shows a short
//  "not set up yet" panel. They advertise no widget sizes, so the dashboard
//  widget picker simply doesn't offer them until they ship. (Speedometer became
//  a real feature in M8.0 — see `SpeedometerFeature`.)
//
//  When a feature is implemented for real it gets its own file (e.g.
//  `SettingsFeature`) and drops out of here — the **id** and manifest identity
//  carry over unchanged, so persisted Home placements and navigation references
//  keep resolving. `settings` in particular is a deliberately stable id for the
//  future `SettingsFeature`.
//

import SwiftUI

@MainActor
final class PlaceholderFeature: DashFeature {

    let manifest: FeatureManifest
    private let blurb: String

    init(
        id: FeatureID,
        title: String,
        symbolName: String,
        tint: FeatureTint,
        iconAssetName: String?,
        blurb: String
    ) {
        self.manifest = FeatureManifest(
            id: id,
            title: title,
            symbolName: symbolName,
            supportedSizes: [.full],
            defaultSize: .full,
            iconStyle: .pinned(tint),
            iconAssetName: iconAssetName
        )
        self.blurb = blurb
    }

    private lazy var fullScreen = AnyView(
        PlaceholderFeatureView(manifest: manifest, blurb: blurb)
    )

    func makeFullScreenView() -> AnyView { fullScreen }

    /// Never reached through the dashboard (no widget sizes advertised); returns
    /// a matching placeholder so the contract still holds.
    func makeComponentView(size: ComponentSize) -> AnyView {
        AnyView(PlaceholderFeatureView(manifest: manifest, blurb: blurb))
    }
}

extension PlaceholderFeature {

    /// Stable feature ids. A future real feature reuses its id verbatim.
    enum ID {
        static let appleMaps = "apple-maps"
        static let music = "music"
        static let weather = "weather"
        static let settings = "settings"
    }

    static func appleMaps() -> PlaceholderFeature {
        PlaceholderFeature(
            id: ID.appleMaps,
            title: "Apple Maps",
            symbolName: "map.fill",
            tint: .blue,
            iconAssetName: "app-icon-apple-maps",
            blurb: "An Apple Maps view will join Google Maps as a map provider."
        )
    }

    static func music() -> PlaceholderFeature {
        PlaceholderFeature(
            id: ID.music,
            title: "Apple Music",
            symbolName: "music.note",
            tint: .pink,
            iconAssetName: "app-icon-apple-music",
            blurb: "Full Apple Music catalog search and a custom player are on the way."
        )
    }

    static func weather() -> PlaceholderFeature {
        PlaceholderFeature(
            id: ID.weather,
            title: "Weather",
            symbolName: "cloud.sun.fill",
            tint: .teal,
            iconAssetName: "app-icon-weather",
            blurb: "A glanceable weather widget is on the way."
        )
    }

    static func settings() -> PlaceholderFeature {
        PlaceholderFeature(
            id: ID.settings,
            title: "Settings",
            symbolName: "gearshape.fill",
            tint: .graphite,
            iconAssetName: "app-icon-settings",
            blurb: "Appearance, dashboard and connection preferences are on the way."
        )
    }
}

/// The full-screen panel for a not-yet-built feature — styled like the rest of
/// the shell, never a raw error screen.
private struct PlaceholderFeatureView: View {

    let manifest: FeatureManifest
    let blurb: String

    var body: some View {
        VStack(spacing: DashMetrics.spacingMedium) {
            DashAppIcon(manifest: manifest, size: 96)

            Text(manifest.title)
                .font(.dashTitle)
                .foregroundStyle(Color.dashTextPrimary)

            Text(blurb)
                .font(.dashCaption)
                .foregroundStyle(Color.dashTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Text("Not set up yet")
                .font(.dashLabel)
                .foregroundStyle(Color.dashTextTertiary)
                .padding(.horizontal, DashMetrics.spacingMedium)
                .padding(.vertical, DashMetrics.spacingTight)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .padding(DashMetrics.spacingLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
