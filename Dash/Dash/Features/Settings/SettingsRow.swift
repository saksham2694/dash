//
//  SettingsRow.swift
//  Dash — Settings feature
//
//  One Apple-style Settings list row: icon + title. The icon reuses
//  `DashAppIcon` — the SAME icon system the Home launcher and sidebar already
//  render a feature with (M8.4 §7) — rather than a second, Settings-only icon
//  mapping. `DashAppIcon` already resolves a feature's local app-icon asset
//  (via `DashLocalAssets`) with a procedural fallback; Settings doesn't
//  reimplement any of that, it just asks for a smaller size.
//

import SwiftUI

/// One Apple-style Settings row label: icon + title. A disclosure chevron
/// appears automatically wherever this sits inside a `NavigationLink`.
struct SettingsRow: View {

    private let icon: DashAppIcon
    private let title: String

    /// A row for a registered feature (the Apps section) — same icon
    /// `DashAppIcon(manifest:)` renders everywhere else in Dash.
    init(manifest: FeatureManifest, title: String? = nil) {
        self.icon = DashAppIcon(manifest: manifest, size: Self.iconSize)
        self.title = title ?? manifest.title
    }

    /// A row with no manifest yet (General, Wallpaper) — `DashAppIcon`'s own
    /// symbol+tint init, the same one a placeholder tile uses.
    init(symbolName: String, tint: FeatureTint, title: String) {
        self.icon = DashAppIcon(symbolName: symbolName, tint: tint, size: Self.iconSize)
        self.title = title
    }

    /// Apple's own Settings-row icon proportions.
    private static let iconSize: CGFloat = 29

    var body: some View {
        Label {
            Text(title)
        } icon: {
            icon
        }
    }
}
