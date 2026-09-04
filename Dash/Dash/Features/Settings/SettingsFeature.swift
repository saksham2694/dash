//
//  SettingsFeature.swift
//  Dash — Settings feature
//
//  The feature's adapter to the shell (M8.3). Replaces the retired
//  `PlaceholderFeature.settings()` — the id and manifest identity carry over
//  unchanged so persisted Home placements and sidebar/navigation references
//  keep resolving.
//
//  Settings owns no runtime state worth surviving a close/reopen — its
//  navigation position is plain SwiftUI `@State` inside `SettingsRootView`,
//  the same way any ordinary Apple-style Settings screen resets to its root
//  when dismissed and reopened. There is no view model to construct here.
//
//  Self-contained (M8.3 §1): this is the ONLY file in the feature that names a
//  `Shell/`-adjacent type (`DashFeature` / `FeatureManifest`, which live under
//  `Features/`, not `Shell/`). Every other Settings file reads what it needs —
//  `FeatureRegistry` (for the Apps list), `Core/WallpaperStore`, and
//  `Core/SpeedUnitStore` — via `@EnvironmentObject`, the same seam every other
//  full-screen feature already uses for its own shared state. Settings never
//  imports `DashboardShell`, the sidebar, the dashboard grid/persistence,
//  `SpeedometerEngine`, or networking.
//
//  Full-screen only (M8.3 §9): `supportedSizes` is `[.full]`, so the dashboard
//  widget picker and validator never offer it as a widget.
//

import SwiftUI

@MainActor
final class SettingsFeature: DashFeature {

    /// Stable id — matches the retired placeholder so nothing has to migrate.
    static let id: FeatureID = "settings"

    let manifest = FeatureManifest(
        id: SettingsFeature.id,
        title: "Settings",
        symbolName: "gearshape.fill",
        supportedSizes: [.full],
        defaultSize: .full,
        iconStyle: .pinned(.graphite),
        iconAssetName: "app-icon-settings"
    )

    private lazy var fullScreenView = AnyView(SettingsRootView())

    func makeFullScreenView() -> AnyView { fullScreenView }

    /// Never reached through the dashboard — Settings advertises no widget
    /// sizes (M8.3 §9); kept total so the `DashFeature` contract still holds.
    func makeComponentView(size: ComponentSize) -> AnyView {
        AnyView(EmptyView())
    }
}
