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
import SwiftUI
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

// MARK: - Compact widget geometry (M9.0 UI pass — position/cropping fix)

@Suite("SpeedometerCompactDial.arcGeometry")
struct SpeedometerCompactArcGeometryTests {

    /// The two aspect ratios the dashboard's unequal-width columns actually
    /// produce (see `DashboardGridGeometry`'s weighted split) — a wide box
    /// (left column, previously height-bound) and a narrow one (right
    /// column, previously width-bound). Both must now leave real margin on
    /// every side, not just whichever one used to happen to have slack.
    @Test("a wide (left-column-shaped) box leaves real top margin", arguments: [
        CGSize(width: 340, height: 150),
        CGSize(width: 300, height: 130),
    ])
    func wideBoxLeavesTopMargin(size: CGSize) {
        guard let (radius, centre) = SpeedometerCompactDial.arcGeometry(for: size, sweepDegrees: 150) else {
            Issue.record("expected valid geometry for \(size)")
            return
        }
        let apexY = centre.y - radius
        #expect(apexY > 0.5, "apex should sit below the box's top edge, not touch it")
    }

    @Test("a narrow (right-column-shaped) box leaves real side margin", arguments: [
        CGSize(width: 190, height: 150),
        CGSize(width: 160, height: 140),
    ])
    func narrowBoxLeavesSideMargin(size: CGSize) {
        guard let (radius, centre) = SpeedometerCompactDial.arcGeometry(for: size, sweepDegrees: 150) else {
            Issue.record("expected valid geometry for \(size)")
            return
        }
        let halfSweep = CGFloat(150.0 / 2) * .pi / 180
        let endX = radius * sin(halfSweep)
        #expect(centre.x - endX > 0.5, "the arc's left end should sit right of the box's left edge")
        #expect(centre.x + endX < size.width - 0.5, "the arc's right end should sit left of the box's right edge")
    }

    @Test("degenerate sizes still return nil")
    func degenerateStillNil() {
        #expect(SpeedometerCompactDial.arcGeometry(for: .zero, sweepDegrees: 150) == nil)
        #expect(SpeedometerCompactDial.arcGeometry(for: CGSize(width: 100, height: 100), sweepDegrees: 0) == nil)
    }
}

// MARK: - Medium/full centering (M9.0 UI pass — "centre the gauge as a whole")

@Suite("SpeedometerDial centering")
struct SpeedometerDialCenteringTests {

    private let style = SpeedometerGaugeStyle.standard

    @Test("centring the ring+readout as a block shifts the centre below the box midpoint")
    func shiftsBelowMidpoint() {
        let height: CGFloat = 400
        let radius: CGFloat = 150
        let centreY = SpeedometerDial.centreY(forBoxHeight: height, radius: radius, style: style)
        // The readout is always shorter than the ring's own top half, so the
        // combined block's balance point sits below the box's raw midpoint —
        // i.e. the ring moves down, adding top margin / trimming the bottom.
        #expect(centreY > height / 2)
    }

    @Test("a taller box grows the same way — the offset from the midpoint is independent of box height")
    func offsetIndependentOfHeight() {
        let radius: CGFloat = 150
        let centreY400 = SpeedometerDial.centreY(forBoxHeight: 400, radius: radius, style: style)
        let centreY600 = SpeedometerDial.centreY(forBoxHeight: 600, radius: radius, style: style)
        #expect(abs((centreY400 - 200) - (centreY600 - 300)) < 1e-9)
    }

    @Test("estimated readout height grows with radius and is well under the ring's own radius")
    func readoutHeightIsReasonable() {
        let radius: CGFloat = 150
        let readoutHeight = SpeedometerDial.estimatedReadoutHeight(radius: radius, style: style)
        #expect(readoutHeight > 0)
        #expect(readoutHeight < radius, "the readout shouldn't be as tall as the ring itself")
    }
}
