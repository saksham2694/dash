//
//  SpeedometerViewModel.swift
//  Dash — Speedometer feature
//
//  The feature's app-scoped state: one `SpeedometerEngine` (the single source of
//  truth for the displayed speed, its validity, its smoothing) plus the display
//  unit. Every Speedometer view — full-screen and each dashboard-widget size —
//  reads this one instance, so speed logic and smoothing are never duplicated per
//  size and the UI does no interpolation of its own.
//
//  Driven by the view: a `TimelineView` calls `tick(at:)` ~30×/s while a
//  Speedometer view is on screen. `tick` pulls the latest raw sample + link
//  state from `SpeedometerTelemetry`, feeds the engine, and returns the current
//  `SpeedometerPresentation`. Between packets the engine's closed-form easing
//  does the smoothing — no fake packets, no per-frame accumulator.
//
//  Not `ObservableObject`: the driving `TimelineView` re-renders every frame and
//  the host's `LocationStore` (an `@EnvironmentObject` on the view) re-renders on
//  each packet, so there is nothing to publish.
//

import Foundation

@MainActor
final class SpeedometerViewModel {

    /// Display unit for the digital readout (M8.3). The live views call
    /// `setUnit(_:)` from the shared `SpeedUnitStore` — this view model never
    /// reads `UserDefaults` itself; the store is the one source of truth.
    private(set) var unit: SpeedometerUnit

    private var engine: SpeedometerEngine
    private var telemetry: (any SpeedometerTelemetry)?

    init(unit: SpeedometerUnit = .default, engine: SpeedometerEngine = .init()) {
        self.unit = unit
        self.engine = engine
    }

    /// Wire up the location source. Called from a Speedometer view's `onAppear`
    /// with the host's `LocationStore`. Idempotent.
    func connect(to telemetry: any SpeedometerTelemetry) {
        self.telemetry = telemetry
    }

    /// Advance the engine to `now` from the latest telemetry and return the
    /// presentation to render. Safe to call at any cadence and from more than one
    /// mounted view.
    @discardableResult
    func tick(at now: Date = Date()) -> SpeedometerPresentation {
        switch telemetry?.speedLinkState ?? .waiting {
        case .waiting:
            engine.markUnavailable()
        case .stale:
            engine.markStale()
        case .live:
            if let sample = telemetry?.latestSpeedSample {
                engine.ingest(
                    metresPerSecond: sample.metresPerSecond,
                    fixTime: sample.fixTime,
                    receivedAt: now
                )
            }
        }
        return presentation(at: now)
    }

    /// The gauge/number presentation at `now`. The needle/arc are always the
    /// fixed M8.1 km/h scale; the digital readout honours `unit` (M8.3 — set
    /// via `setUnit(_:)`, sourced from the shared `SpeedUnitStore`). Pure read,
    /// does not advance the engine.
    func presentation(at now: Date = Date()) -> SpeedometerPresentation {
        let mps = engine.displaySpeed(at: now)
        let kmh = SpeedometerUnit.kilometersPerHour.value(fromMetresPerSecond: mps)
        return SpeedometerPresentation(
            speedKmh: max(0, kmh),
            unit: unit,
            availability: engine.availability(at: now)
        )
    }

    /// The engine reading in an explicit unit (for tests, or a caller that
    /// wants a one-off conversion outside the presentation). Does not advance
    /// the engine.
    func reading(at now: Date = Date(), unit: SpeedometerUnit? = nil) -> SpeedometerReading {
        engine.reading(at: now, unit: unit ?? self.unit)
    }

    /// Change the display unit — called by the live Speedometer views
    /// (`SpeedometerGaugeView` / `SpeedometerCompactView`) from
    /// `SpeedUnitStore`, the shared preference Settings edits (M8.3 §4).
    func setUnit(_ unit: SpeedometerUnit) {
        self.unit = unit
    }
}
