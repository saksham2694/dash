//
//  DashThemeTests.swift
//  DashTests
//
//  M5.5.1 — guardrails for the `DashTheme` visual system. Not snapshot tests:
//  these assert the two things the theme genuinely promises —
//    • readable contrast (WCAG relative luminance) for the text / accent / state
//      colours against the grounds they sit on, and a layered surface ramp,
//    • interactive-target and spacing metrics stay sane —
//  so a future palette tweak can't silently regress legibility.
//

import SwiftUI
import Testing
import UIKit
@testable import Dash

// MARK: - WCAG contrast helper (pure)

@MainActor
private func rgb(_ color: Color) -> (r: Double, g: Double, b: Double)? {
    let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    if resolved.getRed(&r, green: &g, blue: &b, alpha: &a) {
        return (Double(r), Double(g), Double(b))
    }
    var w: CGFloat = 0
    if resolved.getWhite(&w, alpha: &a) {
        return (Double(w), Double(w), Double(w))
    }
    return nil
}

private func relativeLuminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
    func channel(_ v: Double) -> Double {
        let v = max(0, min(1, v))
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
}

@MainActor
private func contrast(_ a: Color, _ b: Color) -> Double {
    guard let ca = rgb(a), let cb = rgb(b) else { return 0 }
    let la = relativeLuminance(ca), lb = relativeLuminance(cb)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

// MARK: - Contrast

@MainActor
@Suite("DashTheme contrast")
struct DashThemeContrastTests {

    @Test("primary text is AAA-legible on the app background")
    func primaryOnBackground() {
        #expect(contrast(.dashTextPrimary, .dashBackground) >= 7.0)
    }

    @Test("secondary text meets AA on the app background")
    func secondaryOnBackground() {
        #expect(contrast(.dashTextSecondary, .dashBackground) >= 4.5)
    }

    @Test("tertiary text stays at least AA-large on the app background")
    func tertiaryOnBackground() {
        #expect(contrast(.dashTextTertiary, .dashBackground) >= 3.0)
    }

    @Test("primary and secondary text stay legible on a card surface")
    func textOnCard() {
        #expect(contrast(.dashTextPrimary, .dashCard) >= 7.0)
        #expect(contrast(.dashTextSecondary, .dashCard) >= 4.5)
    }

    @Test("text on the accent fill meets the non-text UI threshold")
    func onAccent() {
        #expect(contrast(.dashOnAccent, .dashAccent) >= 3.0)
    }

    @Test("the danger colour reads against the background")
    func danger() {
        #expect(contrast(.dashDanger, .dashBackground) >= 3.0)
    }

    @Test("the positive/connected status colour reads against the rail surface")
    func positiveStatus() {
        #expect(contrast(.dashPositive, .dashSurface) >= 3.0)
        #expect(contrast(.dashPositive, .dashCard) >= 3.0)
    }

    @Test("the surface ramp is layered — background < surface < card")
    func surfaceRamp() {
        #expect(contrast(.dashSurface, .dashBackground) > 1.05)
        #expect(contrast(.dashCard, .dashSurface) > 1.05)
        #expect(contrast(.dashCard, .dashBackground) > 1.15)
    }
}

// MARK: - Metrics

@Suite("DashTheme metrics")
struct DashThemeMetricTests {

    @Test("interactive targets stay at least the 44pt minimum")
    func tapTargets() {
        #expect(DashMetrics.minTapTarget >= 44)
        #expect(DashMetrics.controlHeight >= 44)
    }

    @Test("the spacing scale is positive and strictly increasing")
    func spacingScale() {
        let scale = [
            DashMetrics.spacingTight,
            DashMetrics.spacingSmall,
            DashMetrics.spacingMedium,
            DashMetrics.spacingLarge,
        ]
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
        #expect(scale.allSatisfy { $0 > 0 })
    }

    @Test("radii are positive and a card is at least as soft as a control")
    func radii() {
        #expect(DashMetrics.controlCornerRadius > 0)
        #expect(DashMetrics.cardCornerRadius >= DashMetrics.controlCornerRadius)
        #expect(DashMetrics.hairline > 0)
        #expect(DashMetrics.focusStroke > DashMetrics.hairline)
    }
}
