//
//  MusicComponentView.swift
//  Dash — Apple Music feature
//
//  The dashboard-widget presentation — all three widget sizes are real for
//  Apple Music, unlike Speedometer/Weather (M9.0 §"Widgets": "do NOT
//  restrict Apple Music to the same size set"). Every size reads the SAME
//  `MusicPlayerViewModel` from `AppleMusicFeature`.
//

import SwiftUI

struct MusicComponentView: View {

    let feature: AppleMusicFeature
    let size: ComponentSize

    var body: some View {
        switch size {
        case .compact:
            MusicCompactView(playerViewModel: feature.playerViewModel, accessViewModel: feature.accessViewModel)
        case .medium:
            MusicMediumView(playerViewModel: feature.playerViewModel, accessViewModel: feature.accessViewModel)
        case .large, .full:
            // `.full` should not reach a *component* view (full goes through
            // `makeFullScreenView`), but keep this total.
            MusicLargeView(playerViewModel: feature.playerViewModel, accessViewModel: feature.accessViewModel)
        }
    }
}
