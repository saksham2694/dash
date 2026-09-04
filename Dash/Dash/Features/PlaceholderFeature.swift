//
//  PlaceholderFeature.swift
//  Dash
//
//  Registered-but-not-yet-implemented features. Music and the Speedometer are
//  real Dash features (spec §6, §7) — they belong in the sidebar and the Home
//  launcher with their own identity now, not as dimmed "coming soon" stand-ins.
//  Their runtime isn't built yet, so opening one full-screen shows a short
//  "not set up yet" panel. They advertise no widget sizes, so the dashboard
//  widget picker simply doesn't offer them until they ship.
//
//  When Music / Speedometer are implemented for real, each gets its own file
//  (`MusicFeature`, `SpeedometerFeature`) and this one goes away — the id and
//  manifest identity carry over so persisted Home placements keep resolving.
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

    static func music() -> PlaceholderFeature {
        PlaceholderFeature(
            id: "music",
            title: "Apple Music",
            symbolName: "music.note",
            tint: .pink,
            iconAssetName: "app-icon-apple-music",
            blurb: "Full Apple Music catalog search and a custom player are on the way."
        )
    }

    static func speedometer() -> PlaceholderFeature {
        PlaceholderFeature(
            id: "speedometer",
            title: "Speedometer",
            symbolName: "speedometer",
            tint: .orange,
            iconAssetName: "app-icon-speedometer",
            blurb: "A large speed readout and trip computer are on the way."
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
