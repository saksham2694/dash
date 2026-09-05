//
//  MusicFormatting.swift
//  Dash — Apple Music feature
//
//  Pure formatting helpers — one place instead of scattered time-math in the
//  views.
//

import Foundation

nonisolated enum MusicFormatting {

    /// `"3:45"` — never negative, never NaN.
    static func timeText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// `0...1` playback progress, or `0` if the duration isn't known yet.
    static func progress(time: TimeInterval, duration: TimeInterval?) -> Double {
        guard let duration, duration > 0, time.isFinite else { return 0 }
        return min(1, max(0, time / duration))
    }
}
