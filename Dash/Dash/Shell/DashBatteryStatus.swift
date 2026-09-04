//
//  DashBatteryStatus.swift
//  Dash
//
//  Pure presentation for the sidebar's iPhone-battery row (M5.7). Kept out of the
//  view so "which symbol / what text / when de-emphasised" is unit-tested and the
//  view stays declarative. Feeds off `DeviceStatusStore` — the sidebar never
//  reads the network.
//
//  It handles every case the relay can produce: a normal percentage, charging,
//  full, and an intentional *unavailable* state (before the first packet, or
//  after the session drops) — never a bare "—".
//

import DashShared
import SwiftUI

/// What the battery row should render right now.
nonisolated struct DashBatteryStatus: Equatable, Sendable {

    /// SF Symbol for the battery glyph.
    let symbolName: String

    /// Short trailing text (`"87%"`, `"Full"`), or `nil` when there is nothing
    /// meaningful to show (unavailable).
    let text: String?

    /// De-emphasise the whole row — used for stale (last-known) or unavailable.
    let isDimmed: Bool

    /// Spoken description.
    let accessibilityLabel: String
}

nonisolated enum DashBatteryFormatter {

    /// Build the row model from `DeviceStatusStore` state.
    ///
    /// - `percent`: whole-percent charge `0...100`, or `nil` when unknown.
    /// - `state`: charging state from the relay.
    /// - `freshness`: `.live` / `.stale` / `.unavailable` from `DeviceStatusStore`.
    static func status(
        percent: Int?,
        state: BatteryState,
        freshness: DeviceStatusStore.Freshness
    ) -> DashBatteryStatus {

        // Nothing usable yet, or nothing was ever received.
        guard freshness != .unavailable, let percent = clampedPercent(percent) else {
            return DashBatteryStatus(
                symbolName: "battery.0",
                text: nil,
                isDimmed: true,
                accessibilityLabel: "iPhone battery unavailable"
            )
        }

        let isStale = (freshness == .stale)
        let charging = state.isPluggedIn
        let isFull = state == .full || percent >= 100

        let symbol: String
        if charging {
            symbol = "battery.100.bolt"
        } else {
            symbol = symbolForLevel(percent)
        }

        let text: String = isFull ? "Full" : "\(percent)%"

        let label: String
        switch (isStale, state) {
        case (true, _):
            label = "iPhone battery \(percent) percent, last known"
        case (false, .charging):
            label = "iPhone battery \(percent) percent, charging"
        case (false, .full):
            label = "iPhone battery full, charging"
        default:
            label = "iPhone battery \(percent) percent"
        }

        return DashBatteryStatus(
            symbolName: symbol,
            text: text,
            isDimmed: isStale,
            accessibilityLabel: label
        )
    }

    // MARK: - Helpers

    private static func clampedPercent(_ percent: Int?) -> Int? {
        guard let percent else { return nil }
        return min(100, max(0, percent))
    }

    /// The discrete battery glyph for a charge level (matches iOS's own buckets).
    private static func symbolForLevel(_ percent: Int) -> String {
        switch percent {
        case ..<13:  return "battery.0"
        case ..<38:  return "battery.25"
        case ..<63:  return "battery.50"
        case ..<88:  return "battery.75"
        default:     return "battery.100"
        }
    }
}
