//
//  SpeedometerGaugeTests.swift
//  DashTests
//
//  The pure `SpeedometerGauge` geometry (M8.1): the fixed 0–200 km/h scale and
//  the speed → fraction → angle mapping the needle and ticks are drawn from. No
//  SwiftUI rendering assertions.
//

import CoreGraphics
import Foundation
import Testing
@testable import Dash

@Suite("SpeedometerGauge")
struct SpeedometerGaugeTests {

    private let g = SpeedometerGauge.standard   // 0…200 km/h, 240° sweep

    // MARK: - Speed → fraction

    @Test("0 / 100 / 200 km/h map to 0 / 0.5 / 1.0 of the scale")
    func keyFractions() {
        #expect(g.fraction(forKmh: 0) == 0)
        #expect(g.fraction(forKmh: 100) == 0.5)
        #expect(g.fraction(forKmh: 200) == 1.0)
    }

    @Test("intermediate speeds map linearly")
    func intermediateFractions() {
        #expect(g.fraction(forKmh: 50) == 0.25)
        #expect(abs(g.fraction(forKmh: 137) - 0.685) < 1e-9)
    }

    @Test("speeds outside 0…max are clamped, not extrapolated")
    func clamped() {
        #expect(g.fraction(forKmh: -20) == 0)
        #expect(g.fraction(forKmh: 250) == 1.0)
        #expect(g.fraction(forKmh: .nan) == 0)
        #expect(g.fraction(forKmh: .infinity) == 1.0)
    }

    // MARK: - Fraction → angle (degrees clockwise from 12 o'clock)

    @Test("the arc is centred on the top: 0 → −120°, mid → 0°, full → +120°")
    func angles() {
        #expect(g.degrees(forFraction: 0) == -120)
        #expect(g.degrees(forFraction: 0.5) == 0)
        #expect(g.degrees(forFraction: 1) == 120)
        #expect(g.startDegrees == -120)
        #expect(g.endDegrees == 120)
    }

    @Test("100 km/h points the needle straight up")
    func hundredIsStraightUp() {
        #expect(g.degrees(forKmh: 100) == 0)
        #expect(g.degrees(forKmh: 0) == g.startDegrees)
        #expect(g.degrees(forKmh: 200) == g.endDegrees)
        #expect(g.degrees(forKmh: 999) == g.endDegrees)   // pinned, never past the end
    }

    // MARK: - Ticks

    @Test("major ticks are every 20 km/h from 0 to 200")
    func majorTicks() {
        #expect(g.majorTicksKmh == [0, 20, 40, 60, 80, 100, 120, 140, 160, 180, 200])
    }

    @Test("minor ticks fall between the majors and never coincide with one")
    func minorTicks() {
        #expect(g.minorTicksKmh == [10, 30, 50, 70, 90, 110, 130, 150, 170, 190])
        #expect(Set(g.minorTicksKmh).isDisjoint(with: Set(g.majorTicksKmh)))
    }

    // MARK: - Geometry helpers

    @Test("unit vectors: top / right / bottom / left")
    func unitVectors() {
        let up = SpeedometerGauge.unitVector(degreesFromTop: 0)
        #expect(abs(up.dx) < 1e-12 && abs(up.dy + 1) < 1e-12)      // (0, -1) screen-up

        let right = SpeedometerGauge.unitVector(degreesFromTop: 90)
        #expect(abs(right.dx - 1) < 1e-12 && abs(right.dy) < 1e-12) // (1, 0)

        let down = SpeedometerGauge.unitVector(degreesFromTop: 180)
        #expect(abs(down.dy - 1) < 1e-12)                           // (0, 1)
    }

    @Test("a point on the dial is `radius` from the centre at the right angle")
    func pointOnCircle() {
        let centre = CGPoint(x: 100, y: 100)
        let p = SpeedometerGauge.point(degreesFromTop: 0, radius: 40, centre: centre)
        #expect(abs(p.x - 100) < 1e-9)
        #expect(abs(p.y - 60) < 1e-9)                               // 40 above centre

        let d = hypot(
            SpeedometerGauge.point(degreesFromTop: 137, radius: 40, centre: centre).x - centre.x,
            SpeedometerGauge.point(degreesFromTop: 137, radius: 40, centre: centre).y - centre.y
        )
        #expect(abs(d - 40) < 1e-6)
    }
}
