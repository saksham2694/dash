//
//  WeatherDetailView.swift
//  Dash — Weather feature
//
//  The medium widget's content — locality + current temperature on the left,
//  condition icon + condition text + today's H:/L: on the right, a hairline
//  separator, ~6 upcoming hours, and (M8.4 "polish pass") a short
//  upcoming-days strip. Composition follows
//  `DesignReferences/weather-medium-widget.jpeg` (positioning/spacing/
//  hierarchy — not literal Apple artwork). Shared verbatim by the full-screen
//  presentation via `isFullScreen`, which only scales type/spacing/icon size
//  — never rearranges the layout — the same "one shared style, different
//  frame" idea `SpeedometerDial` uses for its own full-screen/medium split.
//

import SwiftUI

/// Pure view of one presentation — the live tick is in `WeatherMediumView` /
/// `WeatherView`.
struct WeatherDetailDial: View {

    let presentation: WeatherPresentation
    var isFullScreen: Bool = false

    /// How many upcoming days to show — a short glance strip, not a
    /// 7/10-day forecast; full-screen has more room than the widget.
    private var dayCount: Int { isFullScreen ? 5 : 3 }

    var body: some View {
        ZStack {
            presentation.appearance.gradient
            Color.black.opacity(presentation.appearance.nightScrimOpacity)

            switch presentation {
            case .unavailable, .loading, .failed:
                WeatherStatusContent(presentation: presentation, isFullScreen: isFullScreen)
            case .loaded(let snapshot, let stale):
                content(for: snapshot, stale: stale, appearance: presentation.appearance)
            }
        }
    }

    private func content(for snapshot: WeatherSnapshot, stale: Bool, appearance: WeatherAppearance) -> some View {
        VStack(alignment: .leading, spacing: isFullScreen ? 18 : 10) {
            header(snapshot: snapshot, appearance: appearance)

            if stale {
                Text("Last updated \(snapshot.fetchedAt, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(appearance.secondaryContentColor)
            }

            separator(appearance: appearance)

            hourlyStrip(snapshot: snapshot, appearance: appearance)

            if !snapshot.dailyForecast.isEmpty {
                // A flexible gap this time — it absorbs the leftover height
                // in the widget's frame, so the daily section settles toward
                // the lower portion instead of sitting flush under the
                // hourly strip with empty space beneath it.
                Spacer(minLength: isFullScreen ? 16 : 10)
                dailyForecast(snapshot: snapshot, appearance: appearance)
            }
        }
        .padding(isFullScreen ? 32 : 16)
        .opacity(stale ? 0.75 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Locality + big temperature on the left; icon, condition text and
    /// H:/L: stacked on the right — matches the reference exactly (M8.4
    /// polish pass; the earlier layout put condition/H:L under the
    /// temperature instead).
    private func header(snapshot: WeatherSnapshot, appearance: WeatherAppearance) -> some View {
        HStack(alignment: .top, spacing: isFullScreen ? 20 : 12) {
            VStack(alignment: .leading, spacing: isFullScreen ? 6 : 3) {
                Text(snapshot.localityName ?? "My Location")
                    .font(isFullScreen ? .title2.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(appearance.contentColor)
                    .lineLimit(1)

                Text(WeatherFormatting.temperatureText(snapshot.currentTemperature))
                    .font(.system(size: isFullScreen ? 84 : 54, weight: .thin, design: .rounded))
                    .foregroundStyle(appearance.contentColor)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: isFullScreen ? 8 : 4) {
                Image(systemName: snapshot.symbolName)
                    .font(.system(size: isFullScreen ? 40 : 26, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(appearance.contentColor)

                Text(snapshot.condition.shortLabel)
                    .font(isFullScreen ? .title3.weight(.medium) : .subheadline.weight(.medium))
                    .foregroundStyle(appearance.secondaryContentColor)

                HStack(spacing: 6) {
                    Text("H:\(WeatherFormatting.temperatureText(snapshot.highTemperature))")
                    Text("L:\(WeatherFormatting.temperatureText(snapshot.lowTemperature))")
                }
                .font(isFullScreen ? .body.weight(.medium) : .caption.weight(.medium))
                .foregroundStyle(appearance.secondaryContentColor)
            }
        }
    }

    private func separator(appearance: WeatherAppearance) -> some View {
        Rectangle()
            .fill(appearance.secondaryContentColor.opacity(0.35))
            .frame(height: 1)
    }

    private func hourlyStrip(snapshot: WeatherSnapshot, appearance: WeatherAppearance) -> some View {
        let now = Date()
        return HStack(spacing: 0) {
            ForEach(snapshot.hourly.prefix(6)) { hour in
                WeatherHourlyEntryView(entry: hour, referenceDate: now, appearance: appearance, isFullScreen: isFullScreen)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The upcoming-days strip (M8.4 polish pass §3): day, icon, low → high.
    /// A plain tinted capsule stands in for Apple's precise
    /// temperature-range gradient bar — this is a glance strip, not a
    /// reproduction of Apple's proprietary artwork/algorithm.
    private func dailyForecast(snapshot: WeatherSnapshot, appearance: WeatherAppearance) -> some View {
        VStack(alignment: .leading, spacing: isFullScreen ? 10 : 6) {
            ForEach(snapshot.dailyForecast.prefix(dayCount)) { day in
                WeatherDayRow(entry: day, appearance: appearance, isFullScreen: isFullScreen)
            }
        }
    }
}

/// One column of the hourly strip: time, icon, temperature.
private struct WeatherHourlyEntryView: View {

    let entry: WeatherHourEntry
    let referenceDate: Date
    let appearance: WeatherAppearance
    var isFullScreen: Bool = false

    var body: some View {
        VStack(spacing: isFullScreen ? 10 : 6) {
            Text(WeatherFormatting.hourText(for: entry.date, relativeTo: referenceDate))
                .font(isFullScreen ? .subheadline.weight(.medium) : .caption2.weight(.medium))
                .foregroundStyle(appearance.secondaryContentColor)

            Image(systemName: entry.symbolName)
                .font(.system(size: isFullScreen ? 24 : 16, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(appearance.contentColor)

            Text(WeatherFormatting.temperatureText(entry.temperature))
                .font(isFullScreen ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(appearance.contentColor)
        }
    }
}

/// One row of the upcoming-days strip: day, icon, low — bar — high.
private struct WeatherDayRow: View {

    let entry: WeatherDayEntry
    let appearance: WeatherAppearance
    var isFullScreen: Bool = false

    /// The day→icon gap — fixed and tight; these two read as one label.
    private var baseGap: CGFloat { isFullScreen ? 14 : 8 }
    /// Floor for each of the three flexible gaps below — they also share
    /// whatever width the row has left over, which is what actually stretches
    /// the row toward the right edge rather than leaving it short.
    private var flexGapMinimum: CGFloat { isFullScreen ? 16 : 10 }

    var body: some View {
        HStack(spacing: 0) {
            Text(WeatherFormatting.dayText(for: entry.date))
                .font(isFullScreen ? .body.weight(.medium) : .caption.weight(.medium))
                .foregroundStyle(appearance.contentColor)
                .frame(width: isFullScreen ? 56 : 38, alignment: .leading)
                .padding(.trailing, baseGap)

            Image(systemName: entry.symbolName)
                .font(.system(size: isFullScreen ? 20 : 14, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(appearance.contentColor)
                .frame(width: isFullScreen ? 26 : 18)

            // icon → low temp: flexible, shares the row's leftover width.
            Spacer(minLength: flexGapMinimum)

            Text(WeatherFormatting.temperatureText(entry.lowTemperature))
                .font(isFullScreen ? .body : .caption)
                .foregroundStyle(appearance.secondaryContentColor)
                .lineLimit(1)
                .fixedSize()

            // low temp → range bar: flexible.
            Spacer(minLength: flexGapMinimum)

            // Capped, not fully flexible itself — the bar mustn't become the
            // long element; the three `Spacer`s around it are what naturally
            // distribute the row's leftover width instead.
            Capsule()
                .fill(appearance.contentColor.opacity(0.28))
                .frame(maxWidth: isFullScreen ? 250 : 160)
                .frame(height: isFullScreen ? 4 : 3)

            // range bar → high temp: flexible.
            Spacer(minLength: flexGapMinimum)

            Text(WeatherFormatting.temperatureText(entry.highTemperature))
                .font(isFullScreen ? .body.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(appearance.contentColor)
                .lineLimit(1)
                .fixedSize()
                .frame(width: isFullScreen ? 46 : 34, alignment: .trailing)
        }
    }
}

/// The live medium widget — reads `WeatherViewModel` and refreshes on each
/// location update.
struct WeatherMediumView: View {

    @ObservedObject var viewModel: WeatherViewModel
    @EnvironmentObject private var locationStore: LocationStore

    var body: some View {
        WeatherDetailDial(presentation: viewModel.presentation())
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

#if DEBUG
#Preview("Medium — clear day") {
    WeatherDetailDial(presentation: .loaded(.previewClearDay, stale: false))
        .frame(width: 340, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 24))
}
#Preview("Full-screen — clear day") {
    WeatherDetailDial(presentation: .loaded(.previewClearDay, stale: false), isFullScreen: true)
        .frame(width: 760, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 24))
}
#Preview("Medium — states") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(Array(previewPresentations.enumerated()), id: \.offset) { _, presentation in
                WeatherDetailDial(presentation: presentation)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        }
        .padding()
    }
    .background(Color.black)
}

private let previewPresentations: [WeatherPresentation] = [
    .loaded(.previewClearNight, stale: false),
    .loaded(.previewRain, stale: true),
    .loaded(.previewSnow, stale: false),
    .unavailable,
    .loading,
    .failed,
]
#endif
