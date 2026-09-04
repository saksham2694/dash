//
//  SpeedometerFeature.swift
//  Dash — Speedometer feature
//
//  The feature's adapter to the shell and the app-scoped owner of its state
//  (`SpeedometerViewModel`, which owns the one `SpeedometerEngine`). Replaces the
//  M5.6 `PlaceholderFeature.speedometer()` — the id and manifest identity carry
//  over unchanged so persisted Home / dashboard placements keep resolving.
//
//  Self-contained (M8.0 architectural goal): this is the ONLY file in the feature
//  that names a `Shell/` type (`DashFeature` / `FeatureManifest`, which live under
//  `Features/`, not `Shell/`). The engine, view model, units and views know
//  nothing about `DashboardShell`, the sidebar, the dashboard grid, or
//  navigation. Location arrives only via `SpeedometerTelemetry`; the display
//  unit (M8.3) arrives the same way architecturally — the live views read the
//  shared `Core/SpeedUnitStore` via `@EnvironmentObject` (exactly like they
//  already do for `LocationStore`) and forward it into
//  `SpeedometerViewModel.setUnit(_:)`. Settings edits `SpeedUnitStore`; this
//  feature never references Settings, and `SpeedometerEngine` never gains unit
//  awareness — the readout is a display-only conversion of its m/s output.
//

import SwiftUI

@MainActor
final class SpeedometerFeature: DashFeature {

    /// Stable id — matches the retired placeholder so nothing has to migrate.
    static let id: FeatureID = "speedometer"

    /// `.large` is **intentionally not supported** — the circular cluster does not
    /// read at that footprint. The dashboard widget picker and validator honour
    /// `supportedSizes`, so a large Speedometer widget can't be created.
    let manifest = FeatureManifest(
        id: SpeedometerFeature.id,
        title: "Speedometer",
        symbolName: "speedometer",
        supportedSizes: [.compact, .medium, .full],
        defaultSize: .medium,
        iconStyle: .pinned(.orange),
        iconAssetName: "app-icon-speedometer"
    )

    /// The single source of truth for the smoothed speed — shared by the
    /// full-screen view and every widget size.
    let viewModel: SpeedometerViewModel

    init(viewModel: SpeedometerViewModel? = nil) {
        self.viewModel = viewModel ?? SpeedometerViewModel()
    }

    private lazy var fullScreenView = AnyView(SpeedometerView(viewModel: viewModel))

    func makeFullScreenView() -> AnyView { fullScreenView }

    private var componentViews: [ComponentSize: AnyView] = [:]

    func makeComponentView(size: ComponentSize) -> AnyView {
        if let cached = componentViews[size] { return cached }
        let view = AnyView(SpeedometerComponentView(viewModel: viewModel, size: size))
        componentViews[size] = view
        return view
    }
}
