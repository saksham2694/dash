//
//  MapComponentView.swift
//  Dash
//
//  The Map feature's dashboard widgets (M5.2.1) — the real presentations that
//  replaced the M5.2.0 placeholder. Returned by `MapFeature.makeComponentView(size:)`.
//
//    .large   — a live map (widget-framed) + a compact maneuver card and the
//               remaining distance / time / ETA panel while navigating.
//    .medium  — a smaller live map + a one-line maneuver strip while navigating
//               (or a destination chip while previewing a route).
//    .compact — NO map. Navigating: a glanceable next-maneuver readout with the
//               remaining ETA. Otherwise: the chosen destination + ETA, or a
//               plain "Maps" idle state.
//
//  Every widget observes the SAME app-scoped `MapFeature` view models
//  (`MapViewModel` / `NavigationViewModel` / `DestinationStore`) — it never
//  creates its own. Camera behaviour is automatic (`MapDashboardCamera`); there
//  are no user pan/zoom controls. The full-screen `MapFullScreenView` is
//  untouched.
//

import DashShared
import SwiftUI

// MARK: - Presentation decision (pure)

/// What a Map widget of a given size shows right now.
nonisolated enum MapComponentPresentation: Equatable, Sendable {
    /// A live map (`.large` / `.medium`).
    case liveMap
    /// Compact next-maneuver readout — navigation is active (`.compact`).
    case maneuverGlance
    /// Compact destination + ETA — a destination is set but not navigating (`.compact`).
    case destinationSummary
    /// Compact idle "Maps" state — nothing chosen (`.compact`).
    case idle
}

nonisolated enum MapComponentPresenter {

    static func presentation(
        size: ComponentSize,
        navigating: Bool,
        hasDestination: Bool
    ) -> MapComponentPresentation {
        switch size {
        case .large, .medium, .full:
            return .liveMap
        case .compact:
            if navigating { return .maneuverGlance }
            if hasDestination { return .destinationSummary }
            return .idle
        }
    }
}

// MARK: - Entry

struct MapComponentView: View {

    let feature: MapFeature
    let size: ComponentSize

    var body: some View {
        switch size {
        case .compact:
            MapCompactComponent(feature: feature)
        case .medium:
            MapMediumComponent(feature: feature)
        case .large, .full:
            MapLargeComponent(feature: feature)
        }
    }

    /// The presentation this widget resolves to right now — for tests + docs.
    var presentation: MapComponentPresentation {
        MapComponentPresenter.presentation(
            size: size,
            navigating: feature.navigationViewModel.isActive,
            hasDestination: feature.destinationStore.hasDestination
        )
    }
}

// MARK: - Large

struct MapLargeComponent: View {

    let feature: MapFeature
    @ObservedObject var mapViewModel: MapViewModel
    @ObservedObject var navigationViewModel: NavigationViewModel

    init(feature: MapFeature) {
        self.feature = feature
        _mapViewModel = ObservedObject(wrappedValue: feature.mapViewModel)
        _navigationViewModel = ObservedObject(wrappedValue: feature.navigationViewModel)
    }

    var body: some View {
        MapDashboardMapView(mapViewModel: mapViewModel, navigationViewModel: navigationViewModel, feature: feature)
            .overlay(alignment: .top) {
                if let card = navigationViewModel.maneuverCard {
                    ManeuverGlanceView(card: card)
                        .padding(12)
                }
            }
            .overlay(alignment: .bottom) {
                if let info = bottomInfo {
                    RouteInfoPanelView(info: info)
                        .padding(12)
                }
            }
    }

    private var bottomInfo: RouteInfo? {
        if navigationViewModel.isActive {
            return navigationViewModel.routeInfo()
        }
        if mapViewModel.mode == .destinationPreview, let route = mapViewModel.route {
            return .preview(route: route)
        }
        return nil
    }
}

// MARK: - Medium

struct MapMediumComponent: View {

    let feature: MapFeature
    @ObservedObject var mapViewModel: MapViewModel
    @ObservedObject var navigationViewModel: NavigationViewModel
    @ObservedObject var destinationStore: DestinationStore

    init(feature: MapFeature) {
        self.feature = feature
        _mapViewModel = ObservedObject(wrappedValue: feature.mapViewModel)
        _navigationViewModel = ObservedObject(wrappedValue: feature.navigationViewModel)
        _destinationStore = ObservedObject(wrappedValue: feature.destinationStore)
    }

    var body: some View {
        MapDashboardMapView(mapViewModel: mapViewModel, navigationViewModel: navigationViewModel, feature: feature)
            .overlay(alignment: .bottom) { footer }
    }

    @ViewBuilder
    private var footer: some View {
        if let card = navigationViewModel.maneuverCard {
            ManeuverGlanceView(card: card, compact: true)
                .padding(8)
        } else if mapViewModel.mode == .destinationPreview,
                  let destination = destinationStore.destination {
            DestinationChip(
                name: destination.name,
                detail: mapViewModel.route.map { RouteInfo.preview(route: $0).durationText }
            )
            .padding(8)
        }
    }
}

// MARK: - Compact

struct MapCompactComponent: View {

    let feature: MapFeature
    @ObservedObject var mapViewModel: MapViewModel
    @ObservedObject var navigationViewModel: NavigationViewModel
    @ObservedObject var destinationStore: DestinationStore

    init(feature: MapFeature) {
        self.feature = feature
        _mapViewModel = ObservedObject(wrappedValue: feature.mapViewModel)
        _navigationViewModel = ObservedObject(wrappedValue: feature.navigationViewModel)
        _destinationStore = ObservedObject(wrappedValue: feature.destinationStore)
    }

    var presentation: MapComponentPresentation {
        MapComponentPresenter.presentation(
            size: .compact,
            navigating: navigationViewModel.isActive,
            hasDestination: destinationStore.hasDestination
        )
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(white: 0.11))
            .mapDashboardObserving(feature)
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .maneuverGlance:
            if let card = navigationViewModel.maneuverCard {
                CompactManeuver(card: card, remainingETA: navigationViewModel.routeInfo()?.etaText)
            } else {
                CompactIdle()
            }
        case .destinationSummary:
            CompactDestination(
                name: destinationStore.destination?.name ?? "Destination",
                detail: mapViewModel.route.map { RouteInfo.preview(route: $0).durationText }
            )
        default:
            CompactIdle()
        }
    }
}

// MARK: - Small presentational pieces

/// A stripped maneuver card for widgets — the `ManeuverCard` model without the
/// End / Refresh controls of the full-screen `ManeuverCardView`.
struct ManeuverGlanceView: View {

    let card: ManeuverCard
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            Image(systemName: card.iconSystemName)
                .font(.system(size: compact ? 24 : 32, weight: .semibold))
                .foregroundStyle(Color(uiColor: .label))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                if let distanceText = card.distanceText {
                    Text(distanceText)
                        .font(.system(size: compact ? 18 : 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(uiColor: .label))
                }
                Text(card.primaryText)
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)
                if !compact, let detailText = card.detailText, !detailText.isEmpty {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 8 : 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [card.distanceText, card.primaryText, card.detailText].compactMap { $0 }.joined(separator: ", ")
        )
    }
}

private struct CompactManeuver: View {

    let card: ManeuverCard
    let remainingETA: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: card.iconSystemName)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(card.distanceText ?? card.primaryText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(card.detailText ?? card.primaryText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let remainingETA {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(remainingETA)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                    Text("ETA")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CompactDestination: View {

    let name: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail ?? "Route ready")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
    }
}

private struct CompactIdle: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "map.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 1) {
                Text("Maps")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("No destination")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
    }
}

private struct DestinationChip: View {

    let name: String
    let detail: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill").font(.caption)
            Text(name).lineLimit(1)
            if let detail {
                Text("· \(detail)").foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
    }
}
