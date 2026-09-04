//
//  SpeedometerViewModelTests.swift
//  DashTests
//
//  `SpeedometerUnit` conversions + `SpeedometerViewModel` driving the engine
//  from a fake `SpeedometerTelemetry` (no `LocationStore`, no network).
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

    @Test("with no telemetry connected the reading is unavailable")
    func noTelemetry() {
        let vm = SpeedometerViewModel()
        #expect(vm.tick(at: t0).availability == .unavailable)
        #expect(vm.tick(at: t0).text == "–")
    }

    @Test("a live sample flows through to the reading in the chosen unit")
    func liveSampleFlows() {
        let telemetry = FakeSpeedTelemetry()
        let vm = SpeedometerViewModel(unit: .kilometersPerHour)
        vm.connect(to: telemetry)

        telemetry.speedLinkState = .live
        telemetry.latestSpeedSample = SpeedSample(metresPerSecond: 20, fixTime: t(0))   // 72 km/h

        let reading = vm.tick(at: t(0))
        #expect(reading.availability == .live)
        #expect(reading.whole == 72)
    }

    @Test("re-ticking the same packet many times is a stable no-op")
    func reingestIsIdempotent() {
        let telemetry = FakeSpeedTelemetry()
        let vm = SpeedometerViewModel()
        vm.connect(to: telemetry)
        telemetry.speedLinkState = .live
        telemetry.latestSpeedSample = SpeedSample(metresPerSecond: 10, fixTime: t(0))

        _ = vm.tick(at: t(0))
        for i in 1...50 { _ = vm.tick(at: t(Double(i) * 0.033)) }   // ~1.65 s of frames, no new packet
        #expect(abs(vm.reading(at: t(2)).whole - 36) <= 1)          // sat at 36 km/h
    }

    @Test("a stale link freezes the last reading and reports stale")
    func staleLink() {
        let telemetry = FakeSpeedTelemetry()
        let vm = SpeedometerViewModel()
        vm.connect(to: telemetry)

        telemetry.speedLinkState = .live
        telemetry.latestSpeedSample = SpeedSample(metresPerSecond: 15, fixTime: t(0))
        _ = vm.tick(at: t(0))

        telemetry.speedLinkState = .stale
        let reading = vm.tick(at: t(1))
        #expect(reading.availability == .stale)
        #expect(reading.whole == 54)   // 15 m/s, held
    }

    @Test("the link dropping to waiting resets the reading to unavailable")
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

    @Test("changing the unit re-expresses the same speed")
    func unitSwitch() {
        let telemetry = FakeSpeedTelemetry()
        let vm = SpeedometerViewModel(unit: .kilometersPerHour)
        vm.connect(to: telemetry)
        telemetry.speedLinkState = .live
        telemetry.latestSpeedSample = SpeedSample(metresPerSecond: 26.8224, fixTime: t(0))
        #expect(vm.tick(at: t(0)).whole == 97)

        vm.setUnit(.milesPerHour)
        #expect(vm.reading(at: t(0)).whole == 60)
    }
}
