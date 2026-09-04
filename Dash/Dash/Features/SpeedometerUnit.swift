//
//  SpeedometerUnit.swift
//  Dash
//
//  The Speedometer's display unit. The engine works entirely in **metres per
//  second** (the raw `CLLocation.speed` unit); unit conversion is isolated here
//  so the rest of the feature never hand-rolls a `* 3.6`.
//
//  Lives at `Features/` root (M8.3) — not inside `Features/Speedometer/` —
//  alongside `ComponentSize`, for the same reason: it's cross-cutting
//  vocabulary two features now share, not one feature's private type. The
//  Settings feature's Speedometer settings page offers `allCases` in its unit
//  picker; the Speedometer feature converts with it. Neither imports the
//  other's folder (CLAUDE.md: "a feature never references another feature") —
//  a `Features/`-root type is the same escape hatch `ComponentSize` already
//  uses for the shell ↔ every-feature seam.
//
//  Still self-contained in spirit: no Dash, shell, or SwiftUI types. The
//  persisted preference itself lives in `Core/SpeedUnitStore.swift` (M8.3) —
//  this file only defines the unit's vocabulary and conversion math, never
//  reads or writes `UserDefaults`.
//

import Foundation

nonisolated enum SpeedometerUnit: String, CaseIterable, Sendable, Codable {

    case kilometersPerHour
    case milesPerHour

    /// The default until `SpeedUnitStore` has a saved preference.
    static let `default`: SpeedometerUnit = .kilometersPerHour

    /// Short label shown under the number.
    var abbreviation: String {
        switch self {
        case .kilometersPerHour: return "km/h"
        case .milesPerHour:      return "mph"
        }
    }

    /// The unit's full name, for a Settings picker row.
    var displayName: String {
        switch self {
        case .kilometersPerHour: return "Kilometers per Hour"
        case .milesPerHour:      return "Miles per Hour"
        }
    }

    /// The unit's full name for a screen-reader phrase, e.g.
    /// `"Speed 62 miles per hour"`.
    var accessibilityName: String {
        switch self {
        case .kilometersPerHour: return "kilometres per hour"
        case .milesPerHour:      return "miles per hour"
        }
    }

    /// Multiplier from metres per second to this unit.
    var perMetrePerSecond: Double {
        switch self {
        case .kilometersPerHour: return 3.6
        case .milesPerHour:      return 2.236_936_292_054_402
        }
    }

    /// Convert a metres-per-second value into this unit.
    func value(fromMetresPerSecond mps: Double) -> Double {
        mps * perMetrePerSecond
    }
}
