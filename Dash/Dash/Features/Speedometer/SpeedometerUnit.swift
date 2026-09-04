//
//  SpeedometerUnit.swift
//  Dash — Speedometer feature
//
//  The Speedometer's display unit. The engine works entirely in **metres per
//  second** (the raw `CLLocation.speed` unit); unit conversion is isolated here
//  so the rest of the feature never hand-rolls a `* 3.6`.
//
//  Self-contained: no Dash, shell, or SwiftUI types. A future Settings feature
//  will own the user's stored preference; this milestone hard-defaults to km/h
//  (the car is a 2019 Honda Amaze — India — spec §7).
//

import Foundation

nonisolated enum SpeedometerUnit: String, CaseIterable, Sendable, Codable {

    case kilometersPerHour
    case milesPerHour

    /// The default until a Settings feature stores a preference.
    static let `default`: SpeedometerUnit = .kilometersPerHour

    /// Short label shown under the number.
    var abbreviation: String {
        switch self {
        case .kilometersPerHour: return "km/h"
        case .milesPerHour:      return "mph"
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
