//
//  SpeedometerViewModelTests.swift
//  DashTests
//
//  `SpeedometerUnit` conversions + `SpeedometerViewModel` driving the engine from
//  a fake `SpeedometerTelemetry` (no `LocationStore`, no network). The M8.1
//  `tick(at:)` returns a `SpeedometerPresentation` — the needle/arc always on
//  the fixed km/h scale, the digital readout (M8.3) honouring `unit`.
//

import Foundation
import Testing
@testable import Dash

// MARK: - Units

@Suite("SpeedometerUnit")
struct SpeedometerUnitTests {

    @Test("m/s → km/h and mph")
    func conversions() {
        #expect(abs(SpeedometerUnit.kilometersPerHour.value(fromMetresPerSecond: 10) - 36) < 1e-9)
        #expect(abs(SpeedometerUnit.milesPerHour.value(fromMetresPerSecond: 26.8224) - 60) < 1e-3)
        #expect(SpeedometerUnit.kilometersPerHour.value(fromMetresPerSecond: 0) == 0)
    }

    @Test("abbreviations + the default unit")
    func labels() {
        #expect(SpeedometerUnit.kilometersPerHour.abbreviation == "km/h")
        #expect(SpeedometerUnit.milesPerHour.abbreviation == "mph")
        #expect(SpeedometerUnit.default == .kilometersPerHour)
    }
}

// MARK: - Presentation value

@Suite("SpeedometerPresentation")
struct SpeedometerPresentationTests {

    @Test("rounds the number, never negative, en-dash when unavailable")
    func numberFormatting() {
        #expect(SpeedometerPresentation(speedKmh: 51.4, availability: .live).wholeValue == 51)
        #expect(SpeedometerPresentation(speedKmh: 51.6, availability: .live).numberText == "52")
        #expect(SpeedometerPresentation(speedKmh: 0, availability: .live).wholeValue == 0)
        #expect(SpeedometerPresentation(speedKmh: 0, availability: .unavailable).numberText == "–")
    }

    @Test("isMoving reflects a non-zero live speed")
    func moving() {
        #expect(SpeedometerPresentation(speedKmh: 30, availability: .live).isMoving)
        #expect(!SpeedometerPresentation(speedKmh: 0, availability: .live).isMoving)
        #expect(!SpeedometerPresentation(speedKmh: 30, availability: .unavailable).isMoving)
    }

    @Test("defaults to km/h when no unit is specified")
    func defaultsToKmh() {
        let p = SpeedometerPresentation(speedKmh: 72, availability: .live)
        #expect(p.unit == .kilometersPerHour)
        #expect(p.wholeValue == 72)
        #expect(p.unitText == "km/h")
    }

    @Test("mph converts the km/h needle value for the digital readout only")
    func mphConvertsDisplayOnly() {
        // 100 km/h ≈ 62.14 mph.
        let p = SpeedometerPresentation(speedKmh: 100, unit: .milesPerHour, availability: .live)
        #expect(p.wholeValue == 62)
        #expect(p.numberText == "62")
        #expect(p.unitText == "mph")
        // The needle driver is untouched by the unit — still the raw km/h value.
        #expect(abs(p.speedKmh - 100) < 0.001)
    }

    @Test("mph readout is unavailable/en-dash the same as km/h")
    func mphUnavailable() {
        let p = SpeedometerPresentation(speedKmh: 0, unit: .milesPerHour, availability: .unavailable)
        #expect(p.numberText == "–")
        #expect(p.unitText == "mph")
    }
}

// MARK: - View model

@MainActor
final class FakeSpeedTelemetry: SpeedometerTelemetry {
    var latestSpeedSample: SpeedSample?
    var speedLinkState: SpeedometerLinkState = .waiting
}

@MainActor
@Suite("SpeedometerViewModel")
struct SpeedometerViewModelTests {

    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    private func t(_ dt: TimeInterval) -> Date { t0.addingTimeInterval(dt) }

    @Test("with no telemetry connected the presentation is unavailable")
    func noTelemetry() {
        let vm = SpeedometerViewModel()
        #expect(vm.tick(at: t0).availability == .unavailable)
        #expect(vm.tick(at: t0).numberText == "–")
    }

    @Test("a live sample flows through to a km/h presentation")
    func liveSampleFlows() {
        let telemetry = FakeSpeedTelemetry()
        let vm = SpeedometerViewModel()
        vm.connect(to: telemetry)

        telemetry.speedLinkState = .live
        telemetry.latestSpeedSample = SpeedSample(metresPerSecond: 20, fixTime: t(0))   // 72 km/h

        let p = vm.tick(at: t(0))
        #expect(p.availability == .live)
        #expect(p.wholeValue == 72)
        #expect(abs(p.speedKmh - 72) < 0.001)
    }

    @Test("re-ticking the same packet many times is a stable no-op")
    func reingestIsIdempotent() {
        let telemetry = FakeSpeedTelemetry()
        let vm = SpeedometerViewModel()
        vm.connect(to: telemetry)
        telemetry.speedLinkState = .live
        telemetry.latestSpeedSample = SpeedSample(metresPerSecond: 10, fixTime: t(0))   // 36 km/h

        _ = vm.tick(at: t(0))
        for i in 1...50 { _ = vm.tick(at: t(Double(i) * 0.033)) }
        #expect(vm.presentation(at: t(2)).wholeValue == 36)
    }

    @Test("a stale link freezes the last presentation and reports stale")
    func staleLink() {
        let telemetry = FakeSpeedTelemetry()
        let vm = SpeedometerViewModel()
        vm.connect(to: telemetry)

        telemetry.speedLinkState = .live
        telemetry.latestSpeedSample = SpeedSample(metresPerSecond: 15, fixTime: t(0))   // 54 km/h
        _ = vm.tick(at: t(0))

        telemetry.speedLinkState = .stale
        let p = vm.tick(at: t(1))
        #expect(p.availability == .stale)
        #expect(p.wholeValue == 54)
    }

    @Test("the link dropping to waiting resets to unavailable")
    func dropToWaiting() {
        let telemetry = FakeSpeedTelemetry()
        let vm = SpeedometerViewModel()
        vm.connect(to: telemetry)
        telemetry.speedLinkState = .live
        telemetry.latestSpeedSample = SpeedSample(metresPerSecond: 30, fixTime: t(0))
        _ = vm.tick(at: t(0))

        telemetry.speedLinkState = .waiting
        #expect(vm.tick(at: t(1)).availability == .unavailable)
    }

    @Test("the engine reading still honours an explicit unit (Settings hook)")
    func explicitUnitReading() {
        let telemetry = FakeSpeedTelemetry()
        let vm = SpeedometerViewModel(unit: .kilometersPerHour)
        vm.connect(to: telemetry)
        telemetry.speedLinkState = .live
        telemetry.latestSpeedSample = SpeedSample(metresPerSecond: 26.8224, fixTime: t(0))
        _ = vm.tick(at: t(0))

        #expect(vm.reading(at: t(0), unit: .kilometersPerHour).whole == 97)
        #expect(vm.reading(at: t(0), unit: .milesPerHour).whole == 60)
    }

    @Test("setUnit changes the presentation's digital readout without touching the needle value")
    func setUnitChangesReadoutOnly() {
        let telemetry = FakeSpeedTelemetry()
        let vm = SpeedometerViewModel()   // defaults to km/h (SpeedometerUnit.default)
        vm.connect(to: telemetry)
        telemetry.speedLinkState = .live
        telemetry.latestSpeedSample = SpeedSample(metresPerSecond: 26.8224, fixTime: t(0))   // ≈ 96.56 km/h

        let kmh = vm.tick(at: t(0))
        #expect(kmh.unit == .kilometersPerHour)
        #expect(kmh.unitText == "km/h")
        #expect(kmh.wholeValue == 97)

        vm.setUnit(.milesPerHour)
        let mph = vm.presentation(at: t(0))
        #expect(mph.unit == .milesPerHour)
        #expect(mph.unitText == "mph")
        #expect(mph.wholeValue == 60)
        // The needle driver is the same underlying speed either way.
        #expect(abs(mph.speedKmh - kmh.speedKmh) < 0.001)
    }

    @Test("a fresh view model defaults to km/h, matching SpeedometerUnit.default")
    func defaultUnitIsKmh() {
        let vm = SpeedometerViewModel()
        #expect(vm.presentation(at: t0).unit == .kilometersPerHour)
        #expect(SpeedometerUnit.default == .kilometersPerHour)
    }
}
