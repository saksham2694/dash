//
//  SpeedometerComponentView.swift
//  Dash — Speedometer feature
//
//  The dashboard-widget presentation. Two sizes only (large is intentionally
//  unsupported — see `SpeedometerFeature.manifest`):
//
//    • .compact — the speed number is primary, with a restrained semi-circular
//      bar above it (a dedicated compact composition — the full dial doesn't
//      read at this footprint).
//    • .medium  — the EXACT SAME `SpeedometerDial` as the full-screen view, at
//      `SpeedometerGaugeStyle.standard`, just given a smaller frame. Nothing is
//      cropped, simplified, or rearranged — it is the same instrument, scaled.
//
//  Both read the one shared `SpeedometerViewModel`; no speed logic here.
//

import SwiftUI

struct SpeedometerComponentView: View {

    let viewModel: SpeedometerViewModel
    let size: ComponentSize

    var body: some View {
        Group {
            switch size {
            case .compact:
                SpeedometerCompactView(viewModel: viewModel)
            case .medium, .large, .full:
                // `.large` / `.full` should not reach a *component* view (large is
                // unsupported; full goes through `makeFullScreenView`), but keep this
                // total — the same standard gauge is a safe rendering at any size.
                SpeedometerGaugeView(viewModel: viewModel, style: .standard)
            }
        }
        // The dashboard-widget ground (M9.0 UI pass — dashboard widget
        // backgrounds): translucent, not flat black, so the shell's own
        // glass panel behind this widget shows through. `SpeedometerView`
        // (full-screen) keeps its own opaque black ground separately.
        .background(SpeedometerPalette.widgetSurface)
    }
}
