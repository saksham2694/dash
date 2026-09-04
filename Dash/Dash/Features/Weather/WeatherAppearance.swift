//
//  WeatherAppearance.swift
//  Dash — Weather feature
//
//  A small presentation/appearance layer (M8.4 §5) so condition-specific
//  colours live in exactly one place rather than scattered across the compact,
//  medium and full-screen views. `WeatherAppearanceResolver.appearance(for:)`
//  is pure — condition + day/night in, a background gradient + a foreground
//  contrast decision out — so it's trivially unit-tested.
//
//  Deliberately restrained: two gradient stops, one optional night scrim, no
//  per-frame animation cost. Never uses Dash's automotive red accent — this
//  feature owns its own palette entirely.
//

import SwiftUI

nonisolated struct WeatherAppearance: Equatable, Sendable {

    /// Gradient stops, top → bottom.
    var topColor: Color
    var bottomColor: Color

    /// A dark scrim laid over the gradient for a night reading (0 for
    /// already-dark palettes like clear/night or thunderstorm, where a second
    /// darkening pass would just muddy the colour).
    var nightScrimOpacity: Double

    /// Pale backgrounds (snow, fog) need dark text/icons for contrast;
    /// everything else reads better in white — same convention as Apple's own
    /// Weather widgets (M8.4 §5: "text/icon contrast must remain readable").
    var prefersDarkContent: Bool

    var gradient: LinearGradient {
        LinearGradient(colors: [topColor, bottomColor], startPoint: .top, endPoint: .bottom)
    }

    var contentColor: Color { prefersDarkContent ? Color.black.opacity(0.85) : .white }
    var secondaryContentColor: Color { prefersDarkContent ? Color.black.opacity(0.6) : Color.white.opacity(0.78) }

    /// The background while there's no real condition to show yet
    /// (`.unavailable` / `.loading` / `.failed`) — calm and neutral, since it
    /// implies nothing about actual conditions.
    static let neutral = WeatherAppearance(
        topColor: Color(red: 0.16, green: 0.18, blue: 0.22),
        bottomColor: Color(red: 0.26, green: 0.28, blue: 0.33),
        nightScrimOpacity: 0,
        prefersDarkContent: false
    )
}

nonisolated enum WeatherAppearanceResolver {

    /// The appearance for a condition at the given time of day. Total — every
    /// `WeatherCondition` case (including `.other`) resolves to something
    /// sensible, never a crash.
    static func appearance(for condition: WeatherCondition, isDaylight: Bool) -> WeatherAppearance {
        switch condition {
        case .clear:
            return isDaylight
                ? WeatherAppearance(
                    topColor: Color(red: 0.29, green: 0.60, blue: 0.94),
                    bottomColor: Color(red: 0.58, green: 0.80, blue: 0.98),
                    nightScrimOpacity: 0,
                    prefersDarkContent: false
                )
                : WeatherAppearance(
                    topColor: Color(red: 0.04, green: 0.06, blue: 0.20),
                    bottomColor: Color(red: 0.15, green: 0.16, blue: 0.36),
                    nightScrimOpacity: 0,
                    prefersDarkContent: false
                )

        case .partlyCloudy:
            return WeatherAppearance(
                topColor: Color(red: 0.35, green: 0.55, blue: 0.75),
                bottomColor: Color(red: 0.60, green: 0.70, blue: 0.80),
                nightScrimOpacity: isDaylight ? 0 : 0.35,
                prefersDarkContent: false
            )

        case .cloudy:
            return WeatherAppearance(
                topColor: Color(red: 0.46, green: 0.51, blue: 0.57),
                bottomColor: Color(red: 0.63, green: 0.66, blue: 0.70),
                nightScrimOpacity: isDaylight ? 0 : 0.35,
                prefersDarkContent: false
            )

        case .rain:
            return WeatherAppearance(
                topColor: Color(red: 0.26, green: 0.33, blue: 0.44),
                bottomColor: Color(red: 0.42, green: 0.49, blue: 0.58),
                nightScrimOpacity: isDaylight ? 0 : 0.3,
                prefersDarkContent: false
            )

        case .thunderstorm:
            return WeatherAppearance(
                topColor: Color(red: 0.16, green: 0.16, blue: 0.22),
                bottomColor: Color(red: 0.32, green: 0.30, blue: 0.38),
                nightScrimOpacity: 0,
                prefersDarkContent: false
            )

        case .snow:
            return WeatherAppearance(
                topColor: Color(red: 0.70, green: 0.77, blue: 0.84),
                bottomColor: Color(red: 0.87, green: 0.90, blue: 0.94),
                nightScrimOpacity: isDaylight ? 0 : 0.3,
                prefersDarkContent: true
            )

        case .fog, .other:
            return WeatherAppearance(
                topColor: Color(red: 0.62, green: 0.63, blue: 0.62),
                bottomColor: Color(red: 0.78, green: 0.78, blue: 0.75),
                nightScrimOpacity: isDaylight ? 0 : 0.3,
                prefersDarkContent: true
            )
        }
    }
}
