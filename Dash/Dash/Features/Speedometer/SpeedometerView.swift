//
//  SpeedometerView.swift
//  Dash — Speedometer feature
//
//  The full-screen experience: the complete 0–200 km/h instrument cluster on a
//  black ground (`SpeedometerGaugeView` at `.standard` — the same style the
//  medium widget uses, just at the full-screen frame size). The background
//  stays black whatever wallpaper Dash has selected, and the gauge is centred
//  both horizontally and vertically within this feature's content area (it
//  fills the frame `DashboardShell` gives it; it does not know about the
//  sidebar or the shell's own layout).
//

import SwiftUI

struct SpeedometerView: View {

    let viewModel: SpeedometerViewModel

    var body: some View {
        SpeedometerGaugeView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SpeedometerPalette.background)
            .ignoresSafeArea()
    }
}

#if DEBUG
#Preview {
    SpeedometerDial(presentation: SpeedometerPresentation(speedKmh: 64, availability: .live))
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}
#endif
