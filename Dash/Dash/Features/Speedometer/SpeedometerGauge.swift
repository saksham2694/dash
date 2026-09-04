//
//  SpeedometerGauge.swift
//  Dash — Speedometer feature
//
//  Pure gauge geometry: the fixed 0–200 km/h scale and the maths that turns a
//  speed into a needle angle, a progress fraction and tick positions. No SwiftUI
//  (only `Foundation`/`CoreGraphics` for the vector helper) so the mapping is
//  trivially unit-tested and shared by every size.
//
//  Angle convention: **degrees clockwise from 12 o'clock**. A `240°` sweep
//  centred on the top → the scale runs from `-120°` (lower-left, 0 km/h) through
//  `0°` (straight up, 100 km/h) to `+120°` (lower-right, 200 km/h), with a clean
//  120° gap at the bottom — a sporty instrument-cluster layout.
//

import CoreGraphics
import Foundation

nonisolated struct SpeedometerGauge: Equatable, Sendable {

    /// Top of the scale.
    var maxKmh: Double = 200
    /// Total swept angle of the arc, in degrees.
    var sweepDegrees: Double = 240
    /// Labelled / long ticks every this many km/h.
    var majorStepKmh: Double = 20
    /// Short ticks every this many km/h (majors excluded).
    var minorStepKmh: Double = 10

    static let standard = SpeedometerGauge()

    // MARK: - Speed → position

    /// The scale fraction `0…1` for a speed (clamped). `NaN` → 0; `+∞` → 1.
    func fraction(forKmh kmh: Double) -> Double {
        guard maxKmh > 0, !kmh.isNaN else { return 0 }
        return min(1, max(0, kmh / maxKmh))
    }

    /// Degrees clockwise from 12 o'clock for a scale fraction (`0` → arc start,
    /// `1` → arc end). Clamped to the arc.
    func degrees(forFraction f: Double) -> Double {
        let clamped = f.isNaN ? 0 : min(1, max(0, f))
        return -sweepDegrees / 2 + clamped * sweepDegrees
    }

    /// Degrees clockwise from 12 o'clock for a speed. Speeds beyond the scale
    /// pin the needle to the appropriate end.
    func degrees(forKmh kmh: Double) -> Double {
        degrees(forFraction: fraction(forKmh: kmh))
    }

    /// The arc's start / end angle (degrees clockwise from 12 o'clock).
    var startDegrees: Double { -sweepDegrees / 2 }
    var endDegrees: Double { sweepDegrees / 2 }

    // MARK: - Ticks

    /// Major tick speeds: `0, majorStep, … maxKmh`.
    var majorTicksKmh: [Double] {
        Array(stride(from: 0, through: maxKmh, by: majorStepKmh))
    }

    /// Minor tick speeds between the majors.
    var minorTicksKmh: [Double] {
        Array(stride(from: 0, through: maxKmh, by: minorStepKmh))
            .filter { !$0.isMultiple(ofDouble: majorStepKmh) }
    }

    // MARK: - Geometry helpers

    /// Unit vector (`x` → screen-right, `y` → screen-down) pointing along an
    /// angle measured clockwise from 12 o'clock.
    static func unitVector(degreesFromTop d: Double) -> CGVector {
        let r = d * .pi / 180
        return CGVector(dx: sin(r), dy: -cos(r))
    }

    /// A point on a circle of `radius` around `centre`, at an angle clockwise
    /// from 12 o'clock.
    static func point(degreesFromTop d: Double, radius: CGFloat, centre: CGPoint) -> CGPoint {
        let v = unitVector(degreesFromTop: d)
        return CGPoint(x: centre.x + v.dx * radius, y: centre.y + v.dy * radius)
    }
}

private extension Double {
    /// Whole-number multiple test tolerant of binary-float dust.
    func isMultiple(ofDouble step: Double) -> Bool {
        guard step != 0 else { return false }
        let r = (self / step).rounded()
        return abs(self - r * step) < 1e-6
    }
}
