//
//  SpeedometerCompactView.swift
//  Dash — Speedometer feature
//
//  The compact dashboard widget (M8.1, redesigned from
//  `DesignReferences/speedometer-design-reference.png`). Too small for the full
//  circular cluster, so this is a dedicated compact composition: a shallow
//  semi-circular bar (0 → 200 km/h, red fill to the current speed) sits ABOVE
//  the big digital number + "km/h" — the number stays the primary element.
//  Same engine, same red accent, same black ground as the full gauge — the
//  instrument at its smallest, not an unrelated design.
//
//  The arc's radius is solved from the actual box the widget gives it (both the
//  width and height constraints), so it fits cleanly at any compact aspect
//  ratio instead of assuming one.
//
//  M9.0 UI pass — position/cropping fix: the dashboard's two columns are NOT
//  equal width (`DashboardGridGeometry`'s weighted split — the left column is
//  wider than the right), so the SAME compact widget gets a genuinely
//  different aspect-ratio box depending on which column it's placed in. The
//  original `arcGeometry` solved a radius that touched the box's edges with
//  ZERO margin on whichever dimension was tightest — on the wider (left)
//  column the box is width-generous, so the HEIGHT constraint bound instead,
//  landing the apex exactly at `y = 0` (no top margin); on the narrower
//  (right) column the WIDTH constraint bound instead, landing the arc's two
//  ends exactly at the box's left/right edges (no side margin) — either one
//  then gets clipped by the widget's own rounded-card mask. `arcGeometry` now
//  solves the radius against an explicitly inset usable box (below), so
//  there's always real margin on every side regardless of which constraint
//  binds — one geometry, correct at any aspect ratio, no left/right cases.
//

import SwiftUI

/// Pure view of one presentation — the live tick is in `SpeedometerCompactView`.
struct SpeedometerCompactDial: View {

    let presentation: SpeedometerPresentation
    /// A shallower sweep than the full dial — reads as a "semi-circular bar",
    /// not a full instrument. Still the same 0…200 km/h scale.
    var gauge = SpeedometerGauge(sweepDegrees: 150)

    private var dimmed: Bool { presentation.availability != .live }

    var body: some View {
        VStack(spacing: 6) {
            arcBar
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 1) {
                Text(presentation.numberText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(presentation.wholeValue)))
                    .foregroundStyle(dimmed ? SpeedometerPalette.numberDim : SpeedometerPalette.number)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(presentation.unitText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerPalette.caption)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
        .opacity(presentation.availability == .stale ? 0.6 : 1)
        .animation(.snappy(duration: 0.18), value: presentation.wholeValue)
        .animation(.easeInOut(duration: 0.25), value: presentation.availability)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            presentation.availability == .unavailable
                ? "Speed unavailable"
                : "Speed \(presentation.wholeValue) \(presentation.unit.accessibilityName)"
        )
    }

    // MARK: - The semi-circular bar

    private var arcBar: some View {
        Canvas { context, size in
            guard let geometry = SpeedometerCompactDial.arcGeometry(for: size, sweepDegrees: gauge.sweepDegrees) else {
                return
            }
            let (radius, centre) = geometry

            func arcPath(toFraction f: Double) -> Path {
                let startDeg = gauge.degrees(forFraction: 0) - 90
                let endDeg = gauge.degrees(forFraction: f) - 90
                var p = Path()
                p.addArc(center: centre, radius: radius,
                         startAngle: .degrees(startDeg), endAngle: .degrees(endDeg), clockwise: false)
                return p
            }

            let lineWidth = max(3, size.height * 0.16)
            context.stroke(arcPath(toFraction: 1), with: .color(SpeedometerPalette.track),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            if presentation.availability != .unavailable {
                let f = gauge.fraction(forKmh: presentation.speedKmh)
                if f > 0.004 {
                    let color = dimmed ? SpeedometerPalette.accentDim : SpeedometerPalette.accent
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: max(0.5, lineWidth * 0.35)))
                        layer.stroke(arcPath(toFraction: f), with: .color(color.opacity(0.6)),
                                    style: StrokeStyle(lineWidth: lineWidth * 1.6, lineCap: .round))
                    }
                    context.stroke(arcPath(toFraction: f), with: .color(color),
                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }

            // End-of-scale labels, right at the two ends of the track.
            let labelSize = max(9, size.height * 0.22)
            func endLabel(_ text: String, atFraction f: Double, anchor: UnitPoint) {
                let deg = gauge.degrees(forFraction: f)
                let point = SpeedometerGauge.point(degreesFromTop: deg, radius: radius, centre: centre)
                let resolved = context.resolve(
                    Text(text)
                        .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                        .foregroundColor(SpeedometerPalette.scaleDim)
                )
                context.draw(resolved, at: CGPoint(x: point.x, y: point.y + labelSize * 0.9), anchor: anchor)
            }
            endLabel("0", atFraction: 0, anchor: .topLeading)
            endLabel("200", atFraction: 1, anchor: .topTrailing)
        }
    }

    /// Solve the largest circle radius (and its centre) whose `sweepDegrees`
    /// cap — ends at the bottom of `size`, apex at or above its top — fits
    /// entirely inside `size`, leaving real margin on every side. `nil` for a
    /// degenerate size.
    ///
    /// `horizontalInsetFraction` / `topInsetFraction` reserve margin (as a
    /// fraction of `size`'s own width/height) on whichever side the radius
    /// solve is actually constrained by, so neither the arc's two ends nor
    /// its apex ever land exactly on the box's edge — see this file's header
    /// ("position/cropping fix").
    static func arcGeometry(
        for size: CGSize,
        sweepDegrees: Double,
        horizontalInsetFraction: CGFloat = 0.07,
        topInsetFraction: CGFloat = 0.10
    ) -> (radius: CGFloat, centre: CGPoint)? {
        guard size.width > 0, size.height > 0, sweepDegrees > 0, sweepDegrees < 360 else { return nil }
        let halfSweep: CGFloat = CGFloat(sweepDegrees / 2) * .pi / 180
        let sinHalf = sin(halfSweep)
        let cosHalf = cos(halfSweep)
        guard sinHalf > 0.0001 else { return nil }

        let horizontalInset = size.width * horizontalInsetFraction
        let topInset = size.height * topInsetFraction
        let usableWidth = max(0, size.width - horizontalInset * 2)
        let usableHeight = max(0, size.height - topInset)
        guard usableWidth > 0, usableHeight > 0 else { return nil }

        let radiusFromWidth: CGFloat = usableWidth / (2 * sinHalf)
        let radiusFromHeight: CGFloat = (1 - cosHalf) > 0.0001
            ? usableHeight / (1 - cosHalf)
            : .greatestFiniteMagnitude
        let radius: CGFloat = min(radiusFromWidth, radiusFromHeight)
        let centre = CGPoint(x: size.width / 2, y: size.height + radius * cosHalf)
        return (radius, centre)
    }
}

/// The live compact widget — ticks the shared view model each frame. Draws no
/// background of its own — see `SpeedometerGaugeView`'s doc comment; the
/// dashboard widget wrapper (`SpeedometerComponentView`) supplies the
/// translucent widget surface.
struct SpeedometerCompactView: View {

    let viewModel: SpeedometerViewModel

    @EnvironmentObject private var locationStore: LocationStore
    @EnvironmentObject private var speedUnitStore: SpeedUnitStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            SpeedometerCompactDial(presentation: viewModel.tick(at: context.date))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .onAppear {
            viewModel.connect(to: locationStore)
            viewModel.setUnit(speedUnitStore.unit)
        }
        .onChange(of: speedUnitStore.unit) { _, newUnit in
            viewModel.setUnit(newUnit)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 20) {
        ForEach([0.0, 60, 136, 200], id: \.self) { v in
            SpeedometerCompactDial(presentation: SpeedometerPresentation(speedKmh: v, availability: .live))
                .frame(width: 320, height: 150)
                .background(Color.black)
        }
    }
    .padding()
    .background(Color.black)
}
#endif
