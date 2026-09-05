//
//  MusicVolumeSlider.swift
//  Dash — Apple Music feature
//
//  The real, interactive system volume control — used by the full-screen
//  Now Playing screen only (M9.0 final interaction cleanup: the large
//  dashboard widget's volume is now a display-only indicator instead, see
//  `MusicVolumeIndicatorView.swift` — this file no longer needs any touch/
//  gesture interception, since it's never embedded inside `WidgetHostView`'s
//  tap-to-open `Button` or the dashboard pager anymore).
//
//  MusicKit itself has no volume API — `MPVolumeView` (MediaPlayer) is the
//  platform-sanctioned way to expose the system audio volume, so this wraps
//  that rather than inventing a custom volume pipeline.
//

import MediaPlayer
import SwiftUI

struct SystemVolumeSlider: UIViewRepresentable {

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
