//
//  SpeedometerEngine.swift
//  Dash — Speedometer feature
//
//  The self-contained speed-processing core. It consumes irregular, timestamped
//  raw speed samples (from the existing `LocationPacket` stream — NO new packet)
//  and produces a smoothly-evolving *display* speed.
//
//  Design notes (M8.0):
//
//  • RAW telemetry vs DISPLAYED speed are separated. Raw arrives ~1 Hz but
//    irregularly (0.5–2 s gaps are normal, multi-second gaps on signal loss —
//    see the Phase-1 findings). The engine never assumes a fixed interval and
//    never invents samples.
//
//  • Smoothing is a **first-order low-pass in closed form** — the simplest
//    explainable choice. When a valid sample arrives the engine snapshots where
//    the display is *right now* and then, for any later time `t`,
//
//        display(t) = target − (target − snapshot) · e^(−(t − anchor) / τ)
//
//    i.e. an exponential ease from wherever it was toward the latest raw speed,
//    reaching ~63 % in τ and ~95 % in 3τ. `τ ≈ 0.6 s` — smooth but still
//    responsive for driving. It needs no per-frame accumulator and no guess
//    about when the next sample lands: the view evaluates `displaySpeed(at:)`
//    every frame. The `target` never leaves the last real sample, so this
//    finishes an in-flight ease toward a *known* value — it does not extrapolate
//    speed forward.
//
//  • Invalid speed (`CLLocation.speed < 0`), out-of-order / duplicate GPS fix
//    times, the stopped/near-zero case, and stale/disconnected links are handled
//    explicitly below.
//
//  Pure value type. No SwiftUI, no networking, no Dash types — trivially unit
//  tested and portable to a standalone app.
//

import Foundation

nonisolated struct SpeedometerEngine: Equatable, Sendable {

    struct Config: Equatable, Sendable {
        /// Low-pass time constant. Larger = smoother + laggier.
        var smoothingTimeConstant: TimeInterval = 0.6
        /// A raw speed at or below this (m/s) is treated as a dead stop, so the
        /// readout parks at exactly 0 instead of chasing GPS jitter (~1.8 km/h).
        var stationaryMetresPerSecond: Double = 0.5
        /// Once the target is 0, snap the display to 0 when it eases below this
        /// instead of crawling asymptotically.
        var displayZeroSnapMetresPerSecond: Double = 0.3
        /// No fresh valid sample for this long ⇒ the reading reports `.stale`.
        var staleAfter: TimeInterval = 5
    }

    /// Freshness of the reading.
    enum Availability: String, Equatable, Sendable {
        /// No valid sample received yet (or the link was torn down).
        case unavailable
        /// A recent valid sample — the display is easing toward live data.
        case live
        /// Had a reading, but nothing fresh for `staleAfter` (or an upstream
        /// "signal lost"). The display has effectively converged; the UI dims it.
        case stale
    }

    var config: Config

    // MARK: - State (private; observed only through the read API)

    /// The raw speed the display is easing toward (m/s, ≥ 0).
    private var target: Double = 0
    /// The display value at the moment the last valid sample was accepted (m/s).
    private var snapshot: Double = 0
    /// iPad wall-clock time the last valid sample was accepted. `nil` ⇒ never.
    private var anchor: Date?
    /// GPS fix time of the last *accepted* sample — for ordering.
    private var lastFixTime: Date?
    /// An upstream "signal lost" before our own `staleAfter` timeout.
    private var explicitlyStale = false

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Input

    /// Feed one raw sample. `metresPerSecond` keeps `CLLocation.speed` semantics
    /// (negative ⇒ the fix couldn't determine speed). `fixTime` is the GPS fix
    /// time (`LocationPacket.timestamp`); `receivedAt` is the iPad wall clock.
    ///
    /// Rejected silently: a `fixTime` not newer than the last accepted one
    /// (out-of-order / duplicate re-poll), and a negative / non-finite speed
    /// (the link may be alive but the speed isn't trustworthy — the last good
    /// value keeps easing and staleness still applies because `anchor` doesn't
    /// advance).
    mutating func ingest(metresPerSecond: Double, fixTime: Date, receivedAt: Date) {
        if let last = lastFixTime, fixTime <= last { return }
        lastFixTime = fixTime

        guard metresPerSecond.isFinite, metresPerSecond >= 0 else { return }

        let firstSample = (anchor == nil)
        snapshot = firstSample ? 0 : displaySpeed(at: receivedAt)
        target = metresPerSecond <= config.stationaryMetresPerSecond ? 0 : metresPerSecond
        anchor = receivedAt
        explicitlyStale = false

        // First real sample: land on it immediately rather than spinning up from 0.
        if firstSample { snapshot = target }
    }

    /// An upstream "signal lost". The display keeps its converged value; the
    /// reading reports `.stale` until a fresh valid sample arrives.
    mutating func markStale() {
        if anchor != nil { explicitlyStale = true }
    }

    /// The session ended (deliberate disconnect / teardown). Reset to nothing.
    mutating func markUnavailable() {
        target = 0
        snapshot = 0
        anchor = nil
        lastFixTime = nil
        explicitlyStale = false
    }

    // MARK: - Output (pure — evaluate every frame)

    /// The smoothed display speed in **m/s** at `time`, always ≥ 0.
    func displaySpeed(at time: Date) -> Double {
        guard let anchor else { return 0 }

        let elapsed = max(0, time.timeIntervalSince(anchor))
        let tau = max(0.01, config.smoothingTimeConstant)
        var value = target - (target - snapshot) * exp(-elapsed / tau)

        if target == 0, value < config.displayZeroSnapMetresPerSecond {
            value = 0
        }
        return max(0, value)
    }

    /// Availability at `time` (applies the `staleAfter` timeout).
    func availability(at time: Date) -> Availability {
        guard let anchor else { return .unavailable }
        if explicitlyStale { return .stale }
        return time.timeIntervalSince(anchor) >= config.staleAfter ? .stale : .live
    }

    /// A full reading at `time`, rounded to a whole number in `unit`.
    func reading(at time: Date, unit: SpeedometerUnit) -> SpeedometerReading {
        let mps = displaySpeed(at: time)
        let whole = Int(unit.value(fromMetresPerSecond: mps).rounded())
        return SpeedometerReading(
            whole: max(0, whole),
            unit: unit,
            availability: availability(at: time)
        )
    }
}

/// A rounded, unit-resolved speed reading for the UI.
nonisolated struct SpeedometerReading: Equatable, Sendable {

    /// Whole-number speed in `unit`. Never negative.
    let whole: Int
    let unit: SpeedometerUnit
    let availability: SpeedometerEngine.Availability

    /// Whether the vehicle is (displayed as) moving.
    var isMoving: Bool { whole > 0 && availability != .unavailable }

    /// `"52"` — or an en-dash placeholder when there is nothing to show.
    var text: String {
        availability == .unavailable ? "–" : "\(whole)"
    }
}
