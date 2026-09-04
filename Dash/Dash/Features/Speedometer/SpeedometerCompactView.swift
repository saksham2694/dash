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
    /// entirely inside `size`. `nil` for a degenerate size.
    static func arcGeometry(for size: CGSize, sweepDegrees: Double) -> (radius: CGFloat, centre: CGPoint)? {
        guard size.width > 0, size.height > 0, sweepDegrees > 0, sweepDegrees < 360 else { return nil }
        let halfSweep: CGFloat = CGFloat(sweepDegrees / 2) * .pi / 180
        let sinHalf = sin(halfSweep)
        let cosHalf = cos(halfSweep)
        guard sinHalf > 0.0001 else { return nil }

        let radiusFromWidth: CGFloat = size.width / (2 * sinHalf)
        let radiusFromHeight: CGFloat = (1 - cosHalf) > 0.0001
            ? size.height / (1 - cosHalf)
            : .greatestFiniteMagnitude
        let radius: CGFloat = min(radiusFromWidth, radiusFromHeight)
        let centre = CGPoint(x: size.width / 2, y: size.height + radius * cosHalf)
        return (radius, centre)
    }
}

/// The live compact widget — ticks the shared view model each frame.
struct SpeedometerCompactView: View {

    let viewModel: SpeedometerViewModel

    @EnvironmentObject private var locationStore: LocationStore
    @EnvironmentObject private var speedUnitStore: SpeedUnitStore

    var body: some View {
        ZStack {
            SpeedometerPalette.background

            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                SpeedometerCompactDial(presentation: viewModel.tick(at: context.date))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
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
