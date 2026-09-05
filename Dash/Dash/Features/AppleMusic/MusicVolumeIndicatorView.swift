//
//  MusicVolumeIndicatorView.swift
//  Dash — Apple Music feature
//
//  Display-only system volume indicator for the large dashboard widget
//  (M9.0 final interaction cleanup — abandoning interactive volume there;
//  the full-screen player keeps the real, interactive `SystemVolumeSlider`
//  untouched). This reads `AVAudioSession.outputVolume` — Apple's standard,
//  read-only way to observe the current system volume level — via KVO, and
//  draws it as a plain static bar. There is no `MPVolumeView` here at all, so
//  there is no touch/drag surface to protect from the widget's tap-to-open
//  `Button` or the dashboard pager — a single inert `onTapGesture {}` (a
//  plain SwiftUI-to-SwiftUI conflict, not the SwiftUI-vs-UIKit-bridge
//  situation `MPVolumeView` was) is all that's needed to keep a touch here
//  from opening the feature.
//

import AVFoundation
import Combine
import SwiftUI

/// Observes the system output volume via KVO. `AVAudioSession.outputVolume`
/// reflects the current volume regardless of who activated the session —
/// this never activates or otherwise configures the session itself, so it
/// can't interfere with MusicKit's own audio session management.
@MainActor
private final class SystemVolumeObserver: ObservableObject {

    @Published private(set) var level: Float

    private var observation: NSKeyValueObservation?

    init() {
        let session = AVAudioSession.sharedInstance()
        level = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let newValue = change.newValue else { return }
            Task { @MainActor in
                self?.level = newValue
            }
        }
    }
}

/// A static bar showing the current system volume level. Never draggable,
/// never changes the volume — display only.
struct SystemVolumeIndicator: View {

    @StateObject private var observer = SystemVolumeObserver()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: max(0, proxy.size.width * CGFloat(observer.level)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System volume")
        .accessibilityValue("\(Int((observer.level * 100).rounded())) percent")
    }
}
