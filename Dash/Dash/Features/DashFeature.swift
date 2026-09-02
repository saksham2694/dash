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

    init(
        id: FeatureID,
        title: String,
        symbolName: String,
        supportedSizes: Set<ComponentSize>,
        defaultSize: ComponentSize
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
    /// shows. For Map (M5.0) this is the existing `ContentView`, unchanged.
    func makeFullScreenView() -> AnyView

    /// A size-appropriate widget view. `size` is a widget size
    /// (`.compact` / `.medium` / `.large`); the full-screen experience comes
    /// from `makeFullScreenView()`. The dashboard grid that calls this arrives
    /// in M5.2 — until then this is only exercised by tests.
    func makeComponentView(size: ComponentSize) -> AnyView
}
