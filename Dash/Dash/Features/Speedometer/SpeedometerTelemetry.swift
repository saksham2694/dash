//
//  SpeedometerTelemetry.swift
//  Dash — Speedometer feature
//
//  The one seam between the Speedometer feature and the rest of Dash. The feature
//  never touches the network, `LocationReceiver`, `ConnectionCoordinator`, or the
//  shell — it only reads this protocol. Dash provides the conformance
//  (`SpeedometerTelemetry+LocationStore`); a future standalone Speedometer app
//  would provide its own.
//
//  Self-contained: only Foundation + this feature's own `SpeedSample`.
//

import Foundation

/// One raw speed sample lifted from a location fix. `metresPerSecond` keeps
/// `CLLocation.speed` semantics — **negative when the fix couldn't determine
/// speed**; the engine handles that.
nonisolated struct SpeedSample: Equatable, Sendable {
    var metresPerSecond: Double
    /// The GPS fix time (`LocationPacket.timestamp`) — one clock, safe for
    /// inter-sample elapsed-time reasoning.
    var fixTime: Date
}

/// Freshness of the underlying location link, mirrored from `LocationStore.Signal`.
nonisolated enum SpeedometerLinkState: Equatable, Sendable {
    /// No session / nothing received.
    case waiting
    /// Fresh fixes arriving.
    case live
    /// Fixes have stopped (watchdog tripped) — last value should be shown frozen.
    case stale
}

/// What the Speedometer needs from its host to run.
@MainActor
protocol SpeedometerTelemetry: AnyObject {

    /// The most recent raw speed sample, or `nil` before the first fix.
    var latestSpeedSample: SpeedSample? { get }

    /// Freshness of the location link right now.
    var speedLinkState: SpeedometerLinkState { get }
}
