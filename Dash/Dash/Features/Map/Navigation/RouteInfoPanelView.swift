//
//  RouteInfoPanelView.swift
//  Dash
//
//  The bottom route-info panel (M4.4): three stats — distance, travel time, ETA.
//  Presentational only; `RouteInfo` decides the numbers and the labels.
//
//  Two looks, driven by `RouteInfo.kind`, so the static route-preview panel is
//  clearly distinct from the live navigation one: the live panel carries a blue
//  edge accent and "Remaining / Time left / ETA" labels; the preview panel is
//  plain material with "Distance / Time / Arrival".
//

import SwiftUI

struct RouteInfoPanelView: View {

    let info: RouteInfo

    var body: some View {
        let labels = info.kind.labels
        HStack(spacing: 0) {
            stat(labels.distance, info.distanceText)
            divider
            stat(labels.duration, info.durationText)
            divider
            stat(labels.eta, info.etaText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: shape)
        .overlay {
            if info.kind == .remaining {
                shape.strokeBorder(Color(uiColor: .systemBlue).opacity(0.55), lineWidth: 1.5)
            }
        }
        .overlay { shape.strokeBorder(Color.primary.opacity(0.08)) }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(labels.distance) \(info.distanceText), "
            + "\(labels.duration) \(info.durationText), "
            + "\(labels.eta) \(info.etaText)"
        )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 28)
    }
}

#if DEBUG
#Preview("Route info") {
    let route = Route(
        polyline: [MapCoordinate(latitude: 0, longitude: 0), MapCoordinate(latitude: 1, longitude: 1)],
        distanceMeters: 12_400,
        duration: .seconds(1_320)
    )
    let progress = NavigationProgress(
        stepIndex: 1, distanceToManeuverMeters: 300,
        distanceRemainingMeters: 4_800, traveledMeters: 7_600, isArrived: false
    )
    return VStack(spacing: 14) {
        RouteInfoPanelView(info: .preview(route: route))
        RouteInfoPanelView(info: .remaining(route: route, progress: progress))
    }
    .padding()
    .frame(maxWidth: 560)
    .background(Color(white: 0.15))
}
#endif
