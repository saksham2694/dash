//
//  SpeedometerStyle.swift
//  Dash — Speedometer feature
//
//  The feature's own visual language — a sporty automotive instrument cluster,
//  redesigned in M8.1 from `DesignReferences/speedometer-design-reference.png`:
//  black ground, clean white scale, one punchy red accent used for the outer
//  ring, an alternating tick rhythm, the needle and the hub. Feature-owned (no
//  `DashTheme`) so the Speedometer looks the same wherever it is embedded and
//  could move to a standalone app unchanged.
//
//  Dimensions are fractions of the gauge radius, so the medium widget renders
//  the exact same instrument at a smaller scale — not a different design.
//

import SwiftUI

enum SpeedometerPalette {
    /// The cluster ground. Stays black regardless of Dash's wallpaper — the
    /// full-screen instrument only (`SpeedometerView`); NOT the dashboard
    /// widget surface, which uses `widgetSurface` instead so the shell's own
    /// glass panel behind it can show through (M9.0 UI pass — dashboard
    /// widget backgrounds).
    static let background = Color.black
    /// The dashboard-widget ground (compact/medium `SpeedometerComponentView`)
    /// — translucent rather than flat black, so it reads as a dark glass
    /// surface over the shell's own panel (`WidgetHostView.dashGlassSurface`)
    /// instead of a flat black rectangle, while still giving the white
    /// numerals/red accent enough contrast. Feature-owned (no `DashTheme`
    /// import), so a plain translucent black rather than the shell's exact tint.
    static let widgetSurface = Color.black.opacity(0.42)
    /// Sporty red — the outer ring, alternating ticks, needle, hub accent.
    static let accent = Color(red: 0.94, green: 0.10, blue: 0.14)
    static let accentDim = Color(red: 0.50, green: 0.11, blue: 0.13)
    /// Scale + numerals.
    static let scale = Color.white
    static let scaleDim = Color.white.opacity(0.5)
    static let track = Color.white.opacity(0.16)
    static let number = Color.white
    static let numberDim = Color.white.opacity(0.5)
    static let caption = Color.white.opacity(0.55)
    static let hubFill = Color(white: 0.09)
}

/// Tuning for `SpeedometerDial` (the full circular instrument). One style is
/// shared by the full-screen view and the medium widget — see the file header.
struct SpeedometerGaugeStyle: Equatable {

    var showsMinorTicks = true
    /// Numerals every this many km/h. `0` ⇒ no numerals.
    var labelEveryKmh: Double = 20
    /// Every 2nd major tick (`0, 40, 80…`) is drawn in the red accent instead of
    /// white — the alternating rhythm from the reference.
    var accentEveryKmh: Double = 40

    // Outer ring (constant chrome — not a value fill).
    var ringInsetFraction: CGFloat = 0.035
    var ringWidthFraction: CGFloat = 0.028
    var ringGlowWidthFraction: CGFloat = 0.11
    var ringGlowBlurFraction: CGFloat = 0.045

    // Ticks
    var tickInsetFraction: CGFloat = 0.075       // gap between the ring and tick outer edge
    var majorTickLengthFraction: CGFloat = 0.115
    var minorTickLengthFraction: CGFloat = 0.05
    var majorTickWidthFraction: CGFloat = 0.016
    var minorTickWidthFraction: CGFloat = 0.008

    // Labels
    var labelInsetFraction: CGFloat = 0.18       // gap between tick inner edge and label
    var labelFontFraction: CGFloat = 0.10
    var minLabelFontPoints: CGFloat = 8

    // Needle — spans from the pivot (0) outward, so the hub can cover its base
    // with no visible gap.
    var needleOuterFraction: CGFloat = 0.78
    var needleBaseWidthFraction: CGFloat = 0.045
    var needleGlowBlurFraction: CGFloat = 0.018

    // Hub — the needle's physical pivot.
    var hubRadiusFraction: CGFloat = 0.082
    var hubRingWidthFraction: CGFloat = 0.013

    // Central readout — anchored by its TOP edge so it never touches the hub
    // regardless of its own text metrics (see `SpeedometerDial`).
    var readoutTopInsetFraction: CGFloat = 0.20  // below centre
    var numberFontFraction: CGFloat = 0.32
    var unitFontFraction: CGFloat = 0.088

    /// The one gauge style — used identically by full-screen and medium.
    static let standard = SpeedometerGaugeStyle()
}
