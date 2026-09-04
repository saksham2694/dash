//
//  DashFeature.swift
//  Dash
//
//  The seam between the CarPlay-style shell and a self-contained feature/app
//  (Map, and later Music, Speedometer, …). A feature exposes exactly three
//  things: a manifest (identity + how it wants to appear), a full-screen view,
//  and a size-appropriate component view. Nothing else.
//
//  Architecture rules (M5 proposal §9):
//    • A feature never imports `Shell/` and never references `ShellStore`,
//      layout, or another feature.
//    • The shell holds features only as `any DashFeature` and never sees a
//      feature's internal view models.
//    • Adding a feature = a new `DashFeature` type + one line in
//      `FeatureRegistry.makeDefault()`. No shell code changes.
//
//  This protocol and `FeatureManifest` live under `Features/`, not `Shell/`, so
//  a feature can conform without depending on the shell.
//

import SwiftUI

/// Stable, persistable identifier for a feature/app. Chosen once and never
/// changed — it keys the sidebar, dashboard placements, and the restored
/// surface, so a rename would orphan saved state.
typealias FeatureID = String

/// One of a small, curated set of automotive icon tints. SDK-neutral (a token,
/// not a `Color`) so `FeatureManifest` stays SwiftUI-free — the shell's
/// `DashAppIcon` maps each case to an actual gradient.
nonisolated enum FeatureTint: String, Sendable, Equatable, CaseIterable, Codable {
    case blue, teal, green, indigo, purple, pink, orange, red, graphite
}

/// A feature's app-icon visual identity. `automatic` lets the shell derive a
/// stable tint from the feature id (so every feature is colourful without extra
/// work); a feature can `pinned` a specific tint when it has a strong identity.
nonisolated enum FeatureIconStyle: Sendable, Equatable {
    case automatic
    case pinned(FeatureTint)
}

/// How a feature wants to identify and present itself. SDK-neutral value type.
nonisolated struct FeatureManifest: Sendable, Equatable, Identifiable {

    /// Stable identity — see `FeatureID`.
    let id: FeatureID

    /// Short, glanceable name for the sidebar and Home tile.
    let title: String

    /// SF Symbol name for the sidebar / Home icon.
    let symbolName: String

    /// The `ComponentSize`s this feature can render. Always includes `.full`
    /// (every feature has a full-screen view); may include widget sizes.
    let supportedSizes: Set<ComponentSize>

    /// The size a fresh dashboard placement should use. Must be in
    /// `supportedSizes`.
    let defaultSize: ComponentSize

    /// The app-icon visual identity (colour treatment). Defaults to `.automatic`.
    let iconStyle: FeatureIconStyle

    /// The `LocalAssets/` (or bundle) image name for this feature's real app
    /// icon, if the developer has supplied one (private dev build). `nil` → the
    /// shell derives `"app-icon-<id>"`. Either way the shell falls back to the
    /// procedural glyph when no image is present, so the committed build never
    /// needs the asset.
    let iconAssetName: String?

    init(
        id: FeatureID,
        title: String,
        symbolName: String,
        supportedSizes: Set<ComponentSize>,
        defaultSize: ComponentSize,
        iconStyle: FeatureIconStyle = .automatic,
        iconAssetName: String? = nil
    ) {
        precondition(
            supportedSizes.contains(defaultSize),
            "FeatureManifest(\(id)): defaultSize \(defaultSize) is not in supportedSizes"
        )
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.supportedSizes = supportedSizes
        self.defaultSize = defaultSize
        self.iconStyle = iconStyle
        self.iconAssetName = iconAssetName
    }

    /// The widget sizes this feature supports (i.e. excluding `.full`).
    var supportedWidgetSizes: Set<ComponentSize> {
        supportedSizes.subtracting([.full])
    }
}

@MainActor
protocol DashFeature: AnyObject {

    /// Identity + presentation hints. Read by the shell to build the sidebar,
    /// the Home launcher, and (later) the dashboard grid.
    var manifest: FeatureManifest { get }

    /// The full-screen experience for this feature — what `ShellSurface.app`
    /// shows. The feature owns any runtime state this view needs (app-scoped),
    /// so opening the feature again observes the same state rather than
    /// rebuilding it.
    func makeFullScreenView() -> AnyView

    /// A size-appropriate widget view. `size` is a widget size
    /// (`.compact` / `.medium` / `.large`); the full-screen experience comes
    /// from `makeFullScreenView()`. The dashboard grid that calls this arrives
    /// in M5.2 — until then this is only exercised by tests.
    func makeComponentView(size: ComponentSize) -> AnyView
}
