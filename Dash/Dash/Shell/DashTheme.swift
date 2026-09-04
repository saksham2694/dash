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
//  Deliberately lightweight: `Color` / `Font` extensions, a `DashMetrics`
//  constant table, one shared press style (`DashPressStyle` / `.dashPress`),
//  and a few `View` helpers. No protocol, no environment injection, no theme
//  engine. (Time-of-day light/dark switching is a separate, later concern —
//  `Core/ThemeManager` in the spec.)
//
//  M5.5.2a / M5.5.2b: the shell sits on `DashShellBackground` (a warm automotive
//  wallpaper). Rail and widget surfaces are **translucent glass** — a thin
//  material with only a light neutral wash — so the wallpaper genuinely bleeds
//  through, the way CarPlay panels sit over the vehicle wallpaper. The whole
//  shell is a rounded, inset container (`DashMetrics.shell*`), not a full-bleed
//  black screen.
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

    /// Positive / connected status. Used only for small status indicators
    /// (e.g. the "connected" dot on the sidebar's device control).
    static let dashPositive = Color(red: 0.30, green: 0.78, blue: 0.42)

    /// A dark translucent scrim behind a small control that floats over live
    /// feature content (e.g. widget edit controls over a moving map).
    static let dashControlScrim = Color.black.opacity(0.5)

    /// The light neutral wash over a widget's `.ultraThinMaterial` — just enough
    /// to unify readability across a colourful wallpaper WITHOUT killing the
    /// translucency. Deliberately faint.
    static let dashPanelTint = Color(white: 0.10).opacity(0.30)

    /// The wash over the navigation rail's material — a touch heavier than a
    /// widget so the rail reads as the app's frame, but still translucent.
    static let dashRailTint = Color(white: 0.09).opacity(0.42)

    /// The soft top highlight along a glass panel's leading edge.
    static let dashGlassHighlight = Color.white.opacity(0.14)
}

// MARK: - Typography roles

extension Font {

    /// Large glanceable titles — screen headers, empty-state lines.
    static let dashTitle = Font.title3.weight(.semibold)

    /// Standard shell control text (Edit / Done / Add Widget, sidebar buttons).
    static let dashControl = Font.callout.weight(.semibold)

    /// A short label beneath an icon (feature app in the rail, home tile).
    static let dashLabel = Font.caption.weight(.medium)

    /// Primary navigation label (Home / Dashboard in the rail) — a size up from
    /// `dashLabel` so the current vehicle space reads at a glance.
    static let dashNavLabel = Font.subheadline.weight(.semibold)

    /// Secondary / hint text.
    static let dashCaption = Font.footnote
}

// MARK: - Metrics

/// Spacing, radii and control sizing. A small role-named table — not a scale to
/// be extended indefinitely.
enum DashMetrics {

    // MARK: Outer shell composition

    /// Inset of the whole rounded shell from the device screen edge. Small — the
    /// wallpaper only peeks around the outside.
    static let shellOuterInset: CGFloat = 10
    /// The shell container's outer corner radius.
    static let shellCornerRadius: CGFloat = 30
    /// Padding between the shell's rounded edge and its content (dashboard grid,
    /// Home grid).
    static let shellContentInset: CGFloat = 12

    /// Gap between dashboard grid cells (and a widget's interior gap).
    static let gridGap: CGFloat = 10

    /// Fraction of the dashboard's column space the wide LEFT column takes (the
    /// large Map surface). The RIGHT supporting stack takes the rest (~0.44).
    static let dashboardLeftColumnFraction: CGFloat = 0.56

    /// A dashboard widget / large surface — generous, CarPlay-like rounding.
    static let cardCornerRadius: CGFloat = 24
    /// A shell control (pill, rail slot, edit chrome).
    static let controlCornerRadius: CGFloat = 16

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

    // MARK: Navigation rail (sidebar)

    /// The fixed rail's width. Icon-focused (no text nav rows) so it stays
    /// narrow, like the persistent CarPlay rail.
    static let railWidth: CGFloat = 104
    /// The rail's inner horizontal padding.
    static let railInset: CGFloat = 12
    /// A rail app-icon's artwork size.
    static let railIconSize: CGFloat = 46
    /// The tappable / selectable slot around a rail icon (≥ 44pt target).
    static let railSlotSize: CGFloat = 60
    /// Vertical gap between rail icons.
    static let railIconGap: CGFloat = 8
}

// MARK: - Press feedback

/// The shell's one press feedback: a small, quick scale + dim. No bounce, no
/// long spring. Kept here so the sidebar, Home tiles, Dashboard widgets and
/// full-screen chrome can all feel identical without redefining it.
struct DashPressStyle: ButtonStyle {

    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DashPressStyle {
    /// `.buttonStyle(.dashPress)` — the shell's standard press feedback.
    static var dashPress: DashPressStyle { DashPressStyle() }
}

// MARK: - Reusable treatments

extension View {

    /// A translucent automotive **glass panel** — a thin blur with only a light
    /// neutral wash, a soft top highlight and a hairline edge, clipped to a
    /// rounded rectangle. The wallpaper genuinely shows through. Used behind
    /// dashboard widgets, empty states and edit chrome.
    ///
    /// `tint` (default `dashPanelTint`) lets the rail use a slightly heavier
    /// wash without a second modifier.
    func dashGlassSurface(
        cornerRadius: CGFloat = DashMetrics.cardCornerRadius,
        tint: Color = Color.dashPanelTint
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(tint))
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [Color.dashGlassHighlight, .clear],
                            startPoint: .top, endPoint: .center
                        )
                    )
                )
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: DashMetrics.hairline))
    }
}
