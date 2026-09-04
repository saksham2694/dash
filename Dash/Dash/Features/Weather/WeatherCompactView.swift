//
//  WeatherCompactView.swift
//  Dash — Weather feature
//
//  The compact dashboard widget. Locality + current temperature on the left,
//  condition icon + condition text + today's H:/L: on the right, and a small
//  hourly strip below — following
//  `DesignReferences/weather-compat-widget.jpeg`'s composition (positioning/
//  spacing/hierarchy, not literal Apple artwork). Fewer, smaller hourly
//  columns than the medium widget's strip and no separator line, since the
//  compact footprint is the shortest dashboard widget size — current
//  conditions stay the clear priority, the strip is a glance, not the point.
//
//  The strip only ever shows the current + upcoming hours: WeatherKit's
//  hourly forecast starts at "now" and looks forward, so there is no past
//  hour to show without a second, separate historical-weather request — not
//  worth adding for a glance strip.
//

import SwiftUI

/// Pure view of one presentation — the live tick is in `WeatherCompactView`.
struct WeatherCompactDial: View {

    let presentation: WeatherPresentation

    var body: some View {
        ZStack {
            presentation.appearance.gradient
            Color.black.opacity(presentation.appearance.nightScrimOpacity)

            switch presentation {
            case .unavailable, .loading, .failed:
                WeatherStatusContent(presentation: presentation)
            case .loaded(let snapshot, let stale):
                content(for: snapshot, stale: stale, appearance: presentation.appearance)
            }
        }
    }

    private func content(for snapshot: WeatherSnapshot, stale: Bool, appearance: WeatherAppearance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(snapshot: snapshot, appearance: appearance)
            hourlyStrip(snapshot: snapshot, appearance: appearance)
        }
        .padding(14)
        .opacity(stale ? 0.6 : 1)
    }

    /// Locality + big temperature on the left; icon, condition text and
    /// H:/L: stacked on the right — matches the reference.
    private func header(snapshot: WeatherSnapshot, appearance: WeatherAppearance) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.localityName ?? "My Location")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appearance.contentColor)
                    .lineLimit(1)

                Text(WeatherFormatting.temperatureText(snapshot.currentTemperature))
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .foregroundStyle(appearance.contentColor)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: snapshot.symbolName)
                    .font(.system(size: 22, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(appearance.contentColor)

                Text(snapshot.condition.shortLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(appearance.secondaryContentColor)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("H:\(WeatherFormatting.temperatureText(snapshot.highTemperature))")
                    Text("L:\(WeatherFormatting.temperatureText(snapshot.lowTemperature))")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(appearance.secondaryContentColor)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A handful of nearby hours — small and glanceable, not a full 6-column
    /// strip; the compact widget's whole height budget is tight.
    private func hourlyStrip(snapshot: WeatherSnapshot, appearance: WeatherAppearance) -> some View {
        let now = Date()
        return HStack(spacing: 0) {
            ForEach(snapshot.hourly.prefix(5)) { hour in
                WeatherCompactHourView(entry: hour, referenceDate: now, appearance: appearance)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One column of the compact widget's hourly strip — smaller than the
/// medium/full-screen version.
private struct WeatherCompactHourView: View {

    let entry: WeatherHourEntry
    let referenceDate: Date
    let appearance: WeatherAppearance

    var body: some View {
        VStack(spacing: 3) {
            Text(WeatherFormatting.hourText(for: entry.date, relativeTo: referenceDate))
                .font(.caption2.weight(.medium))
                .foregroundStyle(appearance.secondaryContentColor)

            Image(systemName: entry.symbolName)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(appearance.contentColor)

            Text(WeatherFormatting.temperatureText(entry.temperature))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(appearance.contentColor)
        }
    }
}

/// The live compact widget — reads `WeatherViewModel` and refreshes on each
/// location update.
struct WeatherCompactView: View {

    @ObservedObject var viewModel: WeatherViewModel
    @EnvironmentObject private var locationStore: LocationStore

    var body: some View {
        WeatherCompactDial(presentation: viewModel.presentation())
            .task { await start() }
            .onChange(of: locationStore.latestPacket) { _, _ in
                Task { await viewModel.locationDidChange() }
            }
    }

    private func start() async {
        viewModel.connect(to: locationStore)
        await viewModel.locationDidChange()
    }
}

extension WeatherCondition {

    /// A short, glanceable label for the compact widget's condition line.
    var shortLabel: String {
        switch self {
        case .clear:        return "Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .cloudy:       return "Cloudy"
        case .rain:         return "Rain"
        case .thunderstorm: return "Thunderstorms"
        case .snow:         return "Snow"
        case .fog:          return "Fog"
        case .other:        return "Mixed"
        }
    }
}

#if DEBUG
#Preview("Compact — loaded") {
    WeatherCompactDial(presentation: .loaded(.previewClearDay, stale: false))
        .frame(width: 340, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 24))
}
#Preview("Compact — states") {
    VStack(spacing: 16) {
        WeatherCompactDial(presentation: .unavailable)
        WeatherCompactDial(presentation: .loading)
        WeatherCompactDial(presentation: .failed)
        WeatherCompactDial(presentation: .loaded(.previewRain, stale: true))
    }
    .frame(width: 340, height: 150)
    .clipShape(RoundedRectangle(cornerRadius: 24))
    .padding()
    .background(Color.black)
}
#endif
