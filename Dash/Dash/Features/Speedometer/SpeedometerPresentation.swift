//
//  SpeedometerPresentation.swift
//  Dash — Speedometer feature
//
//  What every Speedometer view renders — one immutable value per frame from
//  `SpeedometerViewModel`.
//
//  Pure — no SwiftUI. Two different things read `speedKmh`/`unit` for two
//  different purposes, and they're deliberately independent:
//    • `speedKmh` ALWAYS drives the needle/arc via `SpeedometerGauge` — the
//      M8.1 dial is a fixed 0–200 km/h scale (reference-driven, ring + ticks
//      unchanged by M8.3), the same way a car's analog cluster face doesn't
//      change shape when you flip a digital MPH toggle.
//    • `unit` (M8.3 — the Settings ▸ Speedometer preference, via
//      `SpeedUnitStore` → `SpeedometerViewModel.setUnit(_:)`) only affects the
//      DIGITAL readout: `numberText` and `unitText` convert `speedKmh` into
//      the chosen unit. Nobody re-smooths; the engine still only ever works in
//      m/s.
//

import Foundation

nonisolated struct SpeedometerPresentation: Equatable, Sendable {

    /// Smoothed speed in km/h, unrounded, always ≥ 0 — drives the needle/arc.
    let speedKmh: Double

    /// The unit the DIGITAL readout is shown in. Defaults to km/h so every
    /// existing call site (previews, tests) is unaffected unless it opts in.
    var unit: SpeedometerUnit = .default

    /// Freshness of the underlying reading.
    let availability: SpeedometerEngine.Availability

    /// `speedKmh` converted into `unit` — what the digital readout shows.
    /// (`kilometersPerHour.perMetrePerSecond` is exactly `3.6`, so this is
    /// just `speedKmh` scaled by the two units' ratio — no m/s round-trip.)
    private var displayValue: Double {
        unit == .kilometersPerHour
            ? speedKmh
            : speedKmh * (unit.perMetrePerSecond / SpeedometerUnit.kilometersPerHour.perMetrePerSecond)
    }

    /// The central digital number (rounded, never negative), in `unit`.
    var wholeValue: Int { max(0, Int(displayValue.rounded())) }

    /// `"52"`, or an en-dash when there is nothing to show.
    var numberText: String {
        availability == .unavailable ? "–" : "\(wholeValue)"
    }

    /// Whether the vehicle is shown as moving.
    var isMoving: Bool { wholeValue > 0 && availability != .unavailable }

    /// Caption shown under the number — `"km/h"` or `"mph"`, per `unit`.
    var unitText: String { unit.abbreviation }

    /// A neutral zero reading for previews / an unconnected view model.
    static let idle = SpeedometerPresentation(speedKmh: 0, availability: .unavailable)
}
