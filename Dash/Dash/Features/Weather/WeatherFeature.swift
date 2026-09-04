//
//  WeatherFeature.swift
//  Dash — Weather feature
//
//  The feature's adapter to the shell and the app-scoped owner of its state
//  (`WeatherViewModel`). Replaces the M5.6 `PlaceholderFeature.weather()` —
//  the id and manifest identity carry over unchanged so persisted Home /
//  dashboard placements keep resolving.
//
//  Self-contained (M8.4 §1): this is the ONLY file in the feature that names a
//  `Shell/`-adjacent type (`DashFeature` / `FeatureManifest`, which live under
//  `Features/`, not `Shell/`). The service, view model, appearance and views
//  know nothing about `DashboardShell`, the sidebar, or the dashboard grid.
//  Location arrives only via `WeatherLocationSource`.
//
//  `.large` is intentionally NOT supported (M8.4 §1) — like Speedometer, the
//  widget picker and validator honour `supportedSizes`, so a large Weather
//  widget can't be created.
//

import SwiftUI

@MainActor
final class WeatherFeature: DashFeature {

    /// Stable id — matches the retired placeholder so nothing has to migrate.
    static let id: FeatureID = "weather"

    let manifest = FeatureManifest(
        id: WeatherFeature.id,
        title: "Weather",
        symbolName: "cloud.sun.fill",
        supportedSizes: [.compact, .medium, .full],
        defaultSize: .medium,
        iconStyle: .pinned(.teal),
        iconAssetName: "app-icon-weather"
    )

    /// The single source of truth for the fetched weather — shared by the
    /// full-screen view and every widget size.
    let viewModel: WeatherViewModel

    init(viewModel: WeatherViewModel? = nil) {
        self.viewModel = viewModel ?? WeatherViewModel(service: WeatherKitService())
    }

    private lazy var fullScreenView = AnyView(WeatherView(viewModel: viewModel))

    func makeFullScreenView() -> AnyView { fullScreenView }

    private var componentViews: [ComponentSize: AnyView] = [:]

    func makeComponentView(size: ComponentSize) -> AnyView {
        if let cached = componentViews[size] { return cached }
        let view = AnyView(WeatherComponentView(viewModel: viewModel, size: size))
        componentViews[size] = view
        return view
    }
}
