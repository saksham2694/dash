//
//  SpeedometerEngineTests.swift
//  DashTests
//
//  The pure `SpeedometerEngine` (M8.0). No SwiftUI, no networking — timestamped
//  samples in, a smoothed display value out. Covers valid/invalid speed, unit
//  conversion, fix-time ordering, irregular intervals, easing between samples,
//  staleness, the stopped case, sudden changes and delayed/missing samples.
//

import Foundation
import Testing
@testable import Dash

@Suite("SpeedometerEngine")
struct SpeedometerEngineTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func t(_ dt: TimeInterval) -> Date { t0.addingTimeInterval(dt) }

    private func engine(_ config: SpeedometerEngine.Config = .init()) -> SpeedometerEngine {
        SpeedometerEngine(config: config)
    }

    // MARK: - Basics

    @Test("a fresh engine has nothing to show")
    func fresh() {
        let e = engine()
        #expect(e.displaySpeed(at: t0) == 0)
        #expect(e.availability(at: t0) == .unavailable)
        #expect(e.reading(at: t0, unit: .kilometersPerHour).text == "–")
    }

    @Test("the first valid sample lands immediately, no spin-up from zero")
    func firstSampleLandsImmediately() {
        var e = engine()
        e.ingest(metresPerSecond: 15, fixTime: t(0), receivedAt: t(0))
        #expect(e.displaySpeed(at: t(0)) == 15)
        #expect(e.availability(at: t(0)) == .live)
    }

    @Test("an invalid speed (-1) is ignored and never shows a number")
    func invalidSpeedIgnored() {
        var e = engine()
        e.ingest(metresPerSecond: -1, fixTime: t(0), receivedAt: t(0))
        #expect(e.availability(at: t(0)) == .unavailable)
        #expect(e.displaySpeed(at: t(0)) == 0)

        e.ingest(metresPerSecond: .nan, fixTime: t(1), receivedAt: t(1))
        #expect(e.availability(at: t(1)) == .unavailable)
    }

    @Test("an invalid speed after a valid one keeps the last good value easing")
    func invalidAfterValid() {
        var e = engine()
        e.ingest(metresPerSecond: 10, fixTime: t(0), receivedAt: t(0))   // lands at 10
        e.ingest(metresPerSecond: -1, fixTime: t(1), receivedAt: t(1))   // ignored for speed
        #expect(e.displaySpeed(at: t(2)) == 10)                          // still 10
        // …but with no fresh valid sample it eventually reports stale.
        #expect(e.availability(at: t(10)) == .stale)
    }

    @Test("displayed speed is never negative")
    func neverNegative() {
        var e = engine()
        e.ingest(metresPerSecond: 5, fixTime: t(0), receivedAt: t(0))
        e.ingest(metresPerSecond: 0, fixTime: t(1), receivedAt: t(1))
        for dt in stride(from: 0.0, through: 5.0, by: 0.1) {
            #expect(e.displaySpeed(at: t(1 + dt)) >= 0)
        }
    }

    // MARK: - Units

    @Test("km/h conversion")
    func kmhConversion() {
        var e = engine()
        e.ingest(metresPerSecond: 10, fixTime: t(0), receivedAt: t(0))   // 10 m/s = 36 km/h
        #expect(e.reading(at: t(0), unit: .kilometersPerHour).whole == 36)
    }

    @Test("mph conversion")
    func mphConversion() {
        var e = engine()
        e.ingest(metresPerSecond: 26.8224, fixTime: t(0), receivedAt: t(0))  // ≈ 60 mph
        #expect(e.reading(at: t(0), unit: .milesPerHour).whole == 60)
        #expect(e.reading(at: t(0), unit: .kilometersPerHour).whole == 97)   // ≈ 96.6
    }

    // MARK: - Ordering

    @Test("a sample with an older or equal fix time is rejected")
    func fixTimeOrdering() {
        var e = engine()
        e.ingest(metresPerSecond: 20, fixTime: t(5), receivedAt: t(5))
        e.ingest(metresPerSecond: 50, fixTime: t(2), receivedAt: t(6))   // older fix → ignore
        e.ingest(metresPerSecond: 50, fixTime: t(5), receivedAt: t(7))   // equal fix → ignore
        #expect(abs(e.displaySpeed(at: t(100)) - 20) < 0.01)              // stayed at 20
    }

    // MARK: - Easing between samples

    @Test("the display eases exponentially toward a new target between samples")
    func easesBetweenSamples() {
        let tau = 0.6
        var e = engine(.init(smoothingTimeConstant: tau))
        e.ingest(metresPerSecond: 0, fixTime: t(0), receivedAt: t(0))     // at 0
        e.ingest(metresPerSecond: 20, fixTime: t(1), receivedAt: t(1))    // target 20, snapshot ≈ 0

        #expect(abs(e.displaySpeed(at: t(1)) - 0) < 0.05)                          // t = anchor
        #expect(abs(e.displaySpeed(at: t(1 + tau)) - 20 * (1 - exp(-1))) < 0.1)    // ~63%
        #expect(abs(e.displaySpeed(at: t(1 + 3 * tau)) - 20 * (1 - exp(-3))) < 0.1) // ~95%
        #expect(abs(e.displaySpeed(at: t(60)) - 20) < 0.01)                        // converged
    }

    @Test("irregular sample intervals still converge correctly")
    func irregularIntervals() {
        var e = engine()
        e.ingest(metresPerSecond: 10, fixTime: t(0.0), receivedAt: t(0.0))
        e.ingest(metresPerSecond: 12, fixTime: t(0.4), receivedAt: t(0.4))
        e.ingest(metresPerSecond: 11, fixTime: t(2.7), receivedAt: t(2.7))   // long gap
        e.ingest(metresPerSecond: 30, fixTime: t(3.0), receivedAt: t(3.0))
        #expect(abs(e.displaySpeed(at: t(30)) - 30) < 0.01)
        #expect(e.availability(at: t(3.5)) == .live)
    }

    @Test("a sudden large change is eased, not stepped, and does not overshoot")
    func suddenChange() {
        var e = engine()
        e.ingest(metresPerSecond: 30, fixTime: t(0), receivedAt: t(0))
        e.ingest(metresPerSecond: 5, fixTime: t(1), receivedAt: t(1))     // hard brake
        let mid = e.displaySpeed(at: t(1.3))
        #expect(mid < 30 && mid > 5)                                      // between, easing down
        for dt in stride(from: 0.0, through: 5.0, by: 0.1) {
            let v = e.displaySpeed(at: t(1 + dt))
            #expect(v >= 5 - 0.001 && v <= 30 + 0.001)                    // no overshoot
        }
        #expect(abs(e.displaySpeed(at: t(20)) - 5) < 0.05)
    }

    // MARK: - Stopped / near-zero

    @Test("near-zero raw speed parks the readout at exactly 0")
    func stoppedParksAtZero() {
        var e = engine()
        e.ingest(metresPerSecond: 8, fixTime: t(0), receivedAt: t(0))
        e.ingest(metresPerSecond: 0.3, fixTime: t(1), receivedAt: t(1))   // GPS jitter while stopped
        #expect(e.displaySpeed(at: t(10)) == 0)
        #expect(e.reading(at: t(10), unit: .kilometersPerHour).whole == 0)
        #expect(e.reading(at: t(10), unit: .kilometersPerHour).isMoving == false)
    }

    // MARK: - Staleness / missing / delayed

    @Test("no fresh sample for staleAfter marks the reading stale")
    func goesStale() {
        var e = engine(.init(staleAfter: 5))
        e.ingest(metresPerSecond: 25, fixTime: t(0), receivedAt: t(0))
        #expect(e.availability(at: t(4.9)) == .live)
        #expect(e.availability(at: t(5.0)) == .stale)
        // the number is still the last (converged) value while stale
        #expect(abs(e.displaySpeed(at: t(8)) - 25) < 0.05)
    }

    @Test("a delayed sample after a gap resumes live and re-targets")
    func delayedSampleResumes() {
        var e = engine(.init(staleAfter: 5))
        e.ingest(metresPerSecond: 25, fixTime: t(0), receivedAt: t(0))
        #expect(e.availability(at: t(9)) == .stale)

        e.ingest(metresPerSecond: 40, fixTime: t(10), receivedAt: t(10))
        #expect(e.availability(at: t(10.5)) == .live)
        #expect(abs(e.displaySpeed(at: t(30)) - 40) < 0.01)
    }

    @Test("an explicit signal-lost marks stale without losing the value")
    func explicitStale() {
        var e = engine()
        e.ingest(metresPerSecond: 18, fixTime: t(0), receivedAt: t(0))
        e.markStale()
        #expect(e.availability(at: t(1)) == .stale)
        #expect(abs(e.displaySpeed(at: t(3)) - 18) < 0.1)
    }

    @Test("markUnavailable clears everything")
    func unavailableResets() {
        var e = engine()
        e.ingest(metresPerSecond: 40, fixTime: t(0), receivedAt: t(0))
        e.markUnavailable()
        #expect(e.availability(at: t(1)) == .unavailable)
        #expect(e.displaySpeed(at: t(1)) == 0)
        #expect(e.reading(at: t(1), unit: .kilometersPerHour).text == "–")

        // …and a new sample starts fresh (lands immediately again).
        e.ingest(metresPerSecond: 12, fixTime: t(20), receivedAt: t(20))
        #expect(e.displaySpeed(at: t(20)) == 12)
    }
}
