//
//  WeatherView.swift
//  Dash — Weather feature
//
//  The full-screen experience (M8.4 §7): the SAME content as the medium
//  widget — `WeatherDetailDial` — just given the full feature frame and
//  `isFullScreen: true` for larger type/icons/spacing. No weather maps,
//  precipitation charts, wind/UV/air-quality cards, 10-day forecast, or
//  elaborate navigation — those are explicitly out of scope for this
//  milestone.
//

import SwiftUI

struct WeatherView: View {

    @ObservedObject var viewModel: WeatherViewModel
    @EnvironmentObject private var locationStore: LocationStore

    var body: some View {
        WeatherDetailDial(presentation: viewModel.presentation(), isFullScreen: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .task { await start() }
            .onChange(of: locationStore.latestPacket) { _, _ in
                Task { await viewModel.locationDidChange() }
            }
    }

    private func start() async {
        viewModel.connect(to: locationStore)
        await viewModel.locationDidChange()
    }
}

#if DEBUG
#Preview {
    WeatherDetailDial(presentation: .loaded(.previewClearDay, stale: false), isFullScreen: true)
        .ignoresSafeArea()
}
#endif
