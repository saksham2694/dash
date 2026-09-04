//
//  SpeedometerViewModel.swift
//  Dash — Speedometer feature
//
//  The feature's app-scoped state: one `SpeedometerEngine` (the single source of
//  truth) plus the display unit. Every Speedometer view — full-screen and each
//  dashboard-widget size — reads this one instance, so the speed logic is never
//  duplicated per size.
//
//  It is driven by the view: a `TimelineView` calls `tick(at:)` ~30×/s while a
//  Speedometer view is on screen. `tick` pulls the latest raw sample + link
//  state from `SpeedometerTelemetry`, feeds the engine, and returns the current
//  rounded reading. Between packets the engine's closed-form easing does the
//  smoothing — no fake packets, no per-frame accumulator.
//
//  Not `ObservableObject`: the driving `TimelineView` re-renders every frame and
//  the host's `LocationStore` (an `@EnvironmentObject` on the view) re-renders on
//  each packet, so there is nothing to publish.
//

import Foundation

@MainActor
final class SpeedometerViewModel {

    /// Display unit. A future Settings feature will set this; hard-defaulted now.
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
    /// reading to display. Safe to call at any cadence and from more than one
    /// mounted view.
    @discardableResult
    func tick(at now: Date = Date()) -> SpeedometerReading {
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
        return engine.reading(at: now, unit: unit)
    }

    /// Current reading without advancing (for tests / previews).
    func reading(at now: Date = Date()) -> SpeedometerReading {
        engine.reading(at: now, unit: unit)
    }

    /// Change the display unit (a Settings hook for later).
    func setUnit(_ unit: SpeedometerUnit) {
        self.unit = unit
    }
}
