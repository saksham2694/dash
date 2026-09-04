//
//  SpeedometerTelemetryLocationStore.swift
//  Dash — Speedometer feature ↔ Dash bridge
//
//  The ONE file that couples the Speedometer feature to Dash. It teaches Dash's
//  `LocationStore` (the sanctioned single source of truth for received location
//  data — every feature reads it, none touch the network) to satisfy
//  `SpeedometerTelemetry`.
//
//  To extract the Speedometer into its own app: delete this file and provide a
//  conformance backed by that app's own location source.
//

import DashShared
import Foundation

extension LocationStore: SpeedometerTelemetry {

    var latestSpeedSample: SpeedSample? {
        latestPacket.map {
            SpeedSample(metresPerSecond: $0.speed, fixTime: $0.timestamp)
        }
    }

    var speedLinkState: SpeedometerLinkState {
        switch signal {
        case .waiting: return .waiting
        case .live:    return .live
        case .stale:   return .stale
        }
    }
}
