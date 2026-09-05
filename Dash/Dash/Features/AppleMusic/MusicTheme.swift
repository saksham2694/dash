//
//  MusicTheme.swift
//  Dash — Apple Music feature
//
//  A small, self-contained visual language matching the current Apple Music
//  app — NOT Dash's automotive theme (M9.0 §"Design": "do not apply Dash's
//  automotive red theme to the Music feature"). Deliberately its own file
//  rather than importing `DashTheme`/`DashMetrics` — a feature never does
//  that (CLAUDE.md), and Music needs a genuinely different, Apple-Music-like
//  look (near-black system backgrounds, Apple Music's own pink-red accent)
//  rather than Dash's own accent colour.
//

import SwiftUI

enum MusicTheme {

    /// Apple Music's own accent — a warm pink-red, distinct from Dash's
    /// automotive accent colour (used sparingly: the active tab, the
    /// progress fill, the play button).
    static let accent = Color(red: 0.98, green: 0.20, blue: 0.36)

    static let background = Color.black
    static let secondaryBackground = Color(white: 0.11)

    /// The dashboard-widget ground (compact/medium/large `MusicComponentView`)
    /// — translucent rather than flat black, so it reads as a dark glass
    /// surface over the shell's own panel (`WidgetHostView.dashGlassSurface`)
    /// instead of a flat black rectangle, while still giving white text/
    /// artwork enough contrast (M9.0 UI pass — dashboard widget backgrounds).
    /// The full-screen experience (`AppleMusicRootView`/`MusicNowPlayingView`)
    /// keeps the opaque `background` above — that's its intended dark ground,
    /// unrelated to the widget surface.
    static let widgetSurfaceTint = Color.black.opacity(0.42)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.4)

    /// The row/card surface used for search results, library rows, etc.
    static let cardFill = Color.white.opacity(0.06)
}
