//
//  SpeedometerComponentView.swift
//  Dash — Speedometer feature
//
//  The dashboard-widget presentation. Compact / medium / large all show the same
//  smoothed number from the same `SpeedometerViewModel` — only the type scale
//  differs (`large` adds a caption and leaves room for a future gauge). No speed
//  logic here.
//

import SwiftUI

struct SpeedometerComponentView: View {

    let viewModel: SpeedometerViewModel
    let size: ComponentSize

    private var style: SpeedometerReadoutStyle {
        switch size {
        case .compact:      return .compact
        case .medium:       return .medium
        case .large, .full: return .large
        }
    }

    var body: some View {
        SpeedometerReadout(viewModel: viewModel, style: style)
            .padding(size == .compact ? 8 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
