//
//  DashTheme.swift
//  Dash
//
//  Dash's CarPlay-inspired visual system — a small, flat set of native values.
//
//  This is NOT the real CarPlay framework and uses no CarPlay API. Dash is a
//  custom iPad SwiftUI app styled to feel automotive: near-black grounds, a
//  couple of elevated surface greys, ONE restrained accent, large readable
//  type, rounded cards, generous touch targets, minimal clutter, consistent
//  spacing.
//
//  Deliberately lightweight: `Color` / `Font` extensions plus a `DashMetrics`
//  constant table and two `View` helpers. No protocol, no environment
//  injection, no theme engine. (Time-of-day light/dark switching is a separate,
//  later concern — `Core/ThemeManager` in the spec.)
//
//  Shell-owned. Feature code never imports this: the shell styles the frames
//  *around* feature content (screen grounds, card surfaces, chrome), never the
//  content a `DashFeature` renders.
//

import SwiftUI

// MARK: - Palette

extension Color {

    /// The screen ground behind everything.
    static let dashBackground = Color(white: 0.05)

    /// One step up from the ground — the sidebar rail, sheets, empty states.
    static let dashSurface = Color(white: 0.10)

    /// A widget / card face (sits behind feature content, or is the whole face
    /// of an empty / unresolved widget).
    static let dashCard = Color(white: 0.14)

    /// A pressed card face.
    static let dashCardPressed = Color(white: 0.19)

    /// Hairline separators and the default card outline.
    static let dashSeparator = Color.white.opacity(0.09)

    /// A slightly stronger outline for a focused / editing surface.
    static let dashBorder = Color.white.opacity(0.16)

    /// Primary text / icons on dark grounds — maximum contrast.
    static let dashTextPrimary = Color.white

    /// Secondary / caption text. ~9:1 on `dashBackground`.
    static let dashTextSecondary = Color(white: 0.70)

    /// De-emphasised / placeholder text. ~5:1 on `dashBackground`.
    static let dashTextTertiary = Color(white: 0.52)

    /// The single accent — the app's `AccentColor`. Used sparingly: the current
    /// selection, the primary action, a valid drag target.
    static let dashAccent = Color.accentColor

    /// Text / icon colour that sits on top of a filled `dashAccent` surface.
    static let dashOnAccent = Color.white

    /// Destructive actions and invalid states. Always paired with a shape /
    /// icon cue — never the only signal.
    static let dashDanger = Color(red: 0.92, green: 0.30, blue: 0.26)

    /// A dark translucent scrim behind a small control that floats over live
    /// feature content (e.g. widget edit controls over a moving map).
    static let dashControlScrim = Color.black.opacity(0.55)
}

// MARK: - Typography roles

extension Font {

    /// Large glanceable titles — screen headers, empty-state lines.
    static let dashTitle = Font.title3.weight(.semibold)

    /// Standard shell control text (Edit / Done / Add Widget, sidebar buttons).
    static let dashControl = Font.callout.weight(.semibold)

    /// A short label beneath an icon (sidebar button, home tile).
    static let dashLabel = Font.caption.weight(.medium)

    /// Secondary / hint text.
    static let dashCaption = Font.footnote
}

// MARK: - Metrics

/// Spacing, radii and control sizing. A small role-named table — not a scale to
/// be extended indefinitely.
enum DashMetrics {

    /// Inset from a screen edge to its content.
    static let screenInset: CGFloat = 16

    /// Gap between dashboard grid cells (and a widget's interior gap).
    static let gridGap: CGFloat = 12

    static let cardCornerRadius: CGFloat = 20
    static let controlCornerRadius: CGFloat = 14

    static let hairline: CGFloat = 1
    /// Stroke width for a focused / editing outline.
    static let focusStroke: CGFloat = 2

    // A short spacing scale, named by use.
    static let spacingTight: CGFloat = 6
    static let spacingSmall: CGFloat = 10
    static let spacingMedium: CGFloat = 16
    static let spacingLarge: CGFloat = 24

    /// Comfortable minimum interactive target for glance-and-tap use in a car.
    static let minTapTarget: CGFloat = 44
    /// Standard height of a shell chrome control (pill / sidebar button row).
    static let controlHeight: CGFloat = 44

    /// Inset around a small round overlay control (remove / resize handle).
    static let overlayControlInset: CGFloat = 8

    /// Glyph point size inside a shell control.
    static let glyph: CGFloat = 20
    /// Larger glyph for empty / status states.
    static let statusGlyph: CGFloat = 40
}

// MARK: - Reusable treatments

extension View {

    /// The standard full-bleed screen ground.
    func dashScreenBackground() -> some View {
        background(Color.dashBackground.ignoresSafeArea())
    }

    /// The standard card / surface treatment: clip to a rounded rectangle and
    /// draw the hairline outline. The fill is whatever the view already draws
    /// (feature content, or `Color.dashCard` for an empty widget).
    func dashCardSurface(cornerRadius: CGFloat = DashMetrics.cardCornerRadius) -> some View {
        clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.dashSeparator, lineWidth: DashMetrics.hairline)
            )
    }
}
