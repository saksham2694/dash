//
//  WeatherComponentView.swift
//  Dash — Weather feature
//
//  The dashboard-widget presentation. Two sizes only — `.large` is
//  intentionally unsupported (`WeatherFeature.manifest`), the same way
//  Speedometer excludes it:
//
//    • .compact — current conditions only, no hourly strip (too tight).
//    • .medium  — the full `WeatherDetailDial` content: header + H:/L: +
//      ~6-hour strip.
//

import SwiftUI

struct WeatherComponentView: View {

    @ObservedObject var viewModel: WeatherViewModel
    let size: ComponentSize

    var body: some View {
        switch size {
        case .compact:
            WeatherCompactView(viewModel: viewModel)
        case .medium, .large, .full:
            // `.large` / `.full` should not reach a *component* view (large is
            // unsupported; full goes through `makeFullScreenView`), but keep
            // this total — the medium content is a safe rendering at any size.
            WeatherMediumView(viewModel: viewModel)
        }
    }
}
