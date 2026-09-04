//
//  SpeedometerView.swift
//  Dash — Speedometer feature
//
//  M8.0: an intentionally minimal readout — a big number and a unit label. No
//  gauge, no artwork, no elaborate animation. The point of this milestone is to
//  validate the speed data + smoothing; the visual design is M8.1+.
//
//  One `SpeedometerReadoutView` drives every size (full-screen + each widget
//  footprint); only the type scale and whether a "SPEED" caption shows differ.
//  A `TimelineView` ticks the shared `SpeedometerViewModel` ~30×/s while on
//  screen. The feature reads location only through `SpeedometerTelemetry`; the
//  view reaches the host's `LocationStore` from the environment purely to hand
//  it to the view model and to re-render promptly on each packet.
//

import SwiftUI

// MARK: - Type scale per context

struct SpeedometerReadoutStyle: Equatable {
    var numberPointSize: CGFloat
    var unitPointSize: CGFloat
    var showsCaption: Bool

    static let compact    = SpeedometerReadoutStyle(numberPointSize: 46,  unitPointSize: 13, showsCaption: false)
    static let medium     = SpeedometerReadoutStyle(numberPointSize: 78,  unitPointSize: 17, showsCaption: false)
    static let large      = SpeedometerReadoutStyle(numberPointSize: 128, unitPointSize: 22, showsCaption: true)
    static let fullScreen = SpeedometerReadoutStyle(numberPointSize: 210, unitPointSize: 34, showsCaption: true)
}

// MARK: - The readout

struct SpeedometerReadoutView: View {

    let reading: SpeedometerReading
    let style: SpeedometerReadoutStyle

    var body: some View {
        VStack(spacing: style.numberPointSize * 0.03) {
            if style.showsCaption {
                Text("SPEED")
                    .font(.system(size: style.unitPointSize * 0.8, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(.tertiary)
            }

            Text(reading.text)
                .font(.system(size: style.numberPointSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(reading.whole)))
                .foregroundStyle(numberColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(reading.unit.abbreviation)
                .font(.system(size: style.unitPointSize, weight: .medium))
                .foregroundStyle(.secondary)

            if reading.availability == .stale {
                Text("No signal")
                    .font(.system(size: max(10, style.unitPointSize * 0.7), weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(reading.availability == .stale ? 0.6 : 1)
        .animation(.snappy(duration: 0.18), value: reading.whole)
        .animation(.easeInOut(duration: 0.2), value: reading.availability)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var numberColor: Color {
        switch reading.availability {
        case .unavailable: return .secondary
        case .live:        return .primary
        case .stale:       return .primary
        }
    }

    private var accessibilityLabel: String {
        switch reading.availability {
        case .unavailable: return "Speed unavailable"
        case .stale:       return "Speed \(reading.whole) \(reading.unit.abbreviation), no signal"
        case .live:        return "Speed \(reading.whole) \(reading.unit.abbreviation)"
        }
    }
}

// MARK: - Live container (ticks the view model)

/// Wraps `SpeedometerReadoutView` with the ~30 Hz tick + telemetry hookup. Used
/// by both the full-screen view and every widget size.
struct SpeedometerReadout: View {

    let viewModel: SpeedometerViewModel
    let style: SpeedometerReadoutStyle

    @EnvironmentObject private var locationStore: LocationStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            SpeedometerReadoutView(reading: viewModel.tick(at: context.date), style: style)
        }
        .onAppear { viewModel.connect(to: locationStore) }
    }
}

// MARK: - Full-screen experience

struct SpeedometerView: View {

    let viewModel: SpeedometerViewModel

    var body: some View {
        SpeedometerReadout(viewModel: viewModel, style: .fullScreen)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    SpeedometerReadoutView(
        reading: SpeedometerReading(whole: 52, unit: .kilometersPerHour, availability: .live),
        style: .fullScreen
    )
    .preferredColorScheme(.dark)
}
#endif
