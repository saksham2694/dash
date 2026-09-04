//
//  SpeedometerGaugeView.swift
//  Dash — Speedometer feature
//
//  The full circular instrument (M8.1, redesigned from
//  `DesignReferences/speedometer-design-reference.png`): a 0–200 km/h scale with
//  a constant glowing red outer ring (chrome, not a value fill), an alternating
//  white/red tick rhythm, white numerals, a red needle that visibly pivots at a
//  distinct centre hub, and the big digital speed BELOW the hub. Used at
//  full-screen and — at the identical style, just a smaller frame — in the
//  medium widget, so the two are the same instrument at different scales.
//
//  All motion comes from `SpeedometerPresentation.speedKmh` — the engine's
//  already-smoothed value. The `Canvas` redraws each `TimelineView` frame
//  (~30 Hz); there is no second interpolation in the view. The digital
//  readout's unit (M8.3) is a separate, purely textual concern — see
//  `SpeedometerPresentation`.
//

import SwiftUI

/// Draws the dial for one `SpeedometerPresentation`. Pure `View` of its inputs —
/// the live tick happens in `SpeedometerGaugeView`.
struct SpeedometerDial: View {

    let presentation: SpeedometerPresentation
    var gauge: SpeedometerGauge = .standard
    var style: SpeedometerGaugeStyle = .standard

    private var dimmed: Bool { presentation.availability != .live }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack(alignment: .top) {
                Canvas { context, _ in
                    draw(in: &context, radius: radius, centre: centre)
                }

                // Anchored by its TOP edge (not centred), so the number/unit
                // block never touches the hub regardless of its own text
                // metrics — it starts a fixed distance below centre and grows
                // downward from there.
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(0, proxy.size.height / 2 + radius * style.readoutTopInsetFraction))
                    centralReadout(radius: radius)
                    Spacer(minLength: 0)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .opacity(presentation.availability == .stale ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.25), value: presentation.availability)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Canvas

    private func draw(in context: inout GraphicsContext, radius: CGFloat, centre: CGPoint) {
        guard radius > 0 else { return }
        drawRing(&context, centre: centre, radius: radius)
        drawTicksAndLabels(&context, centre: centre, radius: radius)
        drawNeedle(&context, centre: centre, radius: radius)
        drawHub(&context, centre: centre, radius: radius)
    }

    /// The constant glowing red arc — instrument chrome, not a speed fill. Runs
    /// the whole 0–200 scale regardless of the current reading.
    private func drawRing(_ context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        let ringRadius = radius * (1 - style.ringInsetFraction)
        let start = Angle.degrees(gauge.startDegrees - 90)
        let end = Angle.degrees(gauge.endDegrees - 90)
        var path = Path()
        path.addArc(center: centre, radius: ringRadius, startAngle: start, endAngle: end, clockwise: false)

        let color = dimmed ? SpeedometerPalette.accentDim : SpeedometerPalette.accent

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: max(0.5, radius * style.ringGlowBlurFraction)))
            layer.stroke(path, with: .color(color.opacity(0.6)),
                         style: StrokeStyle(lineWidth: radius * style.ringGlowWidthFraction, lineCap: .round))
        }
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: max(1, radius * style.ringWidthFraction), lineCap: .round))
    }

    private func drawTicksAndLabels(_ context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        let ringRadius = radius * (1 - style.ringInsetFraction)
        let tickOuter = ringRadius - radius * style.tickInsetFraction

        func tick(atKmh kmh: Double, length: CGFloat, width: CGFloat, color: Color) {
            let deg = gauge.degrees(forKmh: kmh)
            let outer = SpeedometerGauge.point(degreesFromTop: deg, radius: tickOuter, centre: centre)
            let inner = SpeedometerGauge.point(degreesFromTop: deg, radius: tickOuter - length, centre: centre)
            var p = Path()
            p.move(to: outer); p.addLine(to: inner)
            context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
        }

        if style.showsMinorTicks {
            for kmh in gauge.minorTicksKmh {
                tick(atKmh: kmh,
                     length: radius * style.minorTickLengthFraction,
                     width: radius * style.minorTickWidthFraction,
                     color: dimmed ? SpeedometerPalette.scaleDim : SpeedometerPalette.scale.opacity(0.6))
            }
        }

        let majorLength = radius * style.majorTickLengthFraction
        for kmh in gauge.majorTicksKmh {
            let isAccent = style.accentEveryKmh > 0 && kmh.truncatingRemainder(dividingBy: style.accentEveryKmh) == 0
            let color: Color = isAccent
                ? (dimmed ? SpeedometerPalette.accentDim : SpeedometerPalette.accent)
                : (dimmed ? SpeedometerPalette.scaleDim : SpeedometerPalette.scale)
            tick(atKmh: kmh, length: majorLength, width: radius * style.majorTickWidthFraction, color: color)
        }

        guard style.labelEveryKmh > 0 else { return }
        let fontSize = max(style.minLabelFontPoints, radius * style.labelFontFraction)
        let labelRadius = tickOuter - majorLength - radius * style.labelInsetFraction
        for kmh in gauge.majorTicksKmh where kmh.truncatingRemainder(dividingBy: style.labelEveryKmh) == 0 {
            let deg = gauge.degrees(forKmh: kmh)
            let point = SpeedometerGauge.point(degreesFromTop: deg, radius: labelRadius, centre: centre)
            let text = Text("\(Int(kmh))")
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(dimmed ? SpeedometerPalette.scaleDim : SpeedometerPalette.scale)
            context.draw(context.resolve(text), at: point, anchor: .center)
        }
    }

    /// The needle spans from the pivot (`along: 0`) outward, so its wide base
    /// sits exactly at the centre — `drawHub` then draws on top, covering the
    /// base cleanly rather than leaving a gap.
    private func drawNeedle(_ context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        guard presentation.availability != .unavailable else { return }

        let deg = gauge.degrees(forKmh: presentation.speedKmh)
        let axis = SpeedometerGauge.unitVector(degreesFromTop: deg)
        let perp = CGVector(dx: -axis.dy, dy: axis.dx)
        let outer = radius * style.needleOuterFraction
        let halfBase = radius * style.needleBaseWidthFraction / 2

        func point(_ along: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: centre.x + axis.dx * along + perp.dx * side,
                    y: centre.y + axis.dy * along + perp.dy * side)
        }
        var path = Path()
        path.move(to: point(0, -halfBase))
        path.addLine(to: point(0, halfBase))
        path.addLine(to: point(outer, 0))    // tapered tip
        path.closeSubpath()

        let color = dimmed ? SpeedometerPalette.accentDim : SpeedometerPalette.accent
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: max(0.5, radius * style.needleGlowBlurFraction)))
            layer.fill(path, with: .color(color.opacity(0.65)))
        }
        context.fill(path, with: .color(color))
    }

    /// The needle's pivot — visually distinct, drawn last so it cleanly covers
    /// the needle's base (no gap between needle and hub).
    private func drawHub(_ context: inout GraphicsContext, centre: CGPoint, radius: CGFloat) {
        let hub = radius * style.hubRadiusFraction
        let rect = CGRect(x: centre.x - hub, y: centre.y - hub, width: hub * 2, height: hub * 2)
        let color = dimmed ? SpeedometerPalette.accentDim : SpeedometerPalette.accent

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: max(0.5, radius * 0.02)))
            layer.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.7)),
                        lineWidth: radius * style.hubRingWidthFraction * 1.8)
        }
        context.fill(Path(ellipseIn: rect), with: .color(SpeedometerPalette.hubFill))
        context.stroke(Path(ellipseIn: rect), with: .color(color),
                       lineWidth: max(1, radius * style.hubRingWidthFraction))
    }

    // MARK: - Central readout (number below the pivot)

    @ViewBuilder
    private func centralReadout(radius: CGFloat) -> some View {
        VStack(spacing: radius * 0.02) {
            Text(presentation.numberText)
                .font(.system(size: radius * style.numberFontFraction, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(presentation.wholeValue)))
                .foregroundStyle(dimmed ? SpeedometerPalette.numberDim : SpeedometerPalette.number)
                .lineLimit(1)
                .minimumScaleFactor(0.4)

            Text(presentation.unitText)
                .font(.system(size: radius * style.unitFontFraction, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerPalette.caption)

            if presentation.availability == .stale {
                Text("No signal")
                    .font(.system(size: max(9, radius * style.unitFontFraction * 0.8), weight: .semibold))
                    .foregroundStyle(SpeedometerPalette.accent)
                    .padding(.top, 2)
            }
        }
        .animation(.snappy(duration: 0.18), value: presentation.wholeValue)
        .fixedSize()
        .frame(maxWidth: .infinity)
    }

    private var accessibilityLabel: String {
        let unitName = presentation.unit.accessibilityName
        switch presentation.availability {
        case .unavailable: return "Speed unavailable"
        case .stale:       return "Speed \(presentation.wholeValue) \(unitName), no signal"
        case .live:        return "Speed \(presentation.wholeValue) \(unitName)"
        }
    }
}

/// The live full gauge — ticks the shared view model each frame. Full-screen
/// and the medium widget both use this with the SAME `style`, just a different
/// frame size, so they render the identical instrument at different scales.
struct SpeedometerGaugeView: View {

    let viewModel: SpeedometerViewModel
    var style: SpeedometerGaugeStyle = .standard

    @EnvironmentObject private var locationStore: LocationStore
    @EnvironmentObject private var speedUnitStore: SpeedUnitStore

    var body: some View {
        ZStack {
            SpeedometerPalette.background

            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                SpeedometerDial(presentation: viewModel.tick(at: context.date), style: style)
            }
        }
        .onAppear {
            viewModel.connect(to: locationStore)
            viewModel.setUnit(speedUnitStore.unit)
        }
        // A live change from the Settings ▸ Speedometer screen takes effect
        // immediately while this view is on screen, not just on next launch.
        .onChange(of: speedUnitStore.unit) { _, newUnit in
            viewModel.setUnit(newUnit)
        }
    }
}

#if DEBUG
#Preview("Full gauge — 92 km/h") {
    SpeedometerDial(presentation: SpeedometerPresentation(speedKmh: 92, availability: .live))
        .padding(24)
        .background(Color.black)
}
#Preview("Full gauge — key values") {
    VStack(spacing: 12) {
        ForEach([0.0, 20, 60, 100, 136, 180, 200], id: \.self) { v in
            SpeedometerDial(presentation: SpeedometerPresentation(speedKmh: v, availability: .live))
                .frame(width: 160, height: 160)
        }
    }
    .padding()
    .background(Color.black)
}
#Preview("Medium (scaled) — 128 km/h") {
    SpeedometerDial(presentation: SpeedometerPresentation(speedKmh: 128, availability: .live))
        .frame(width: 190, height: 190)
        .background(Color.black)
}
#Preview("Stale / unavailable") {
    HStack(spacing: 16) {
        SpeedometerDial(presentation: SpeedometerPresentation(speedKmh: 64, availability: .stale))
        SpeedometerDial(presentation: SpeedometerPresentation(speedKmh: 0, availability: .unavailable))
    }
    .padding()
    .background(Color.black)
}
#endif
