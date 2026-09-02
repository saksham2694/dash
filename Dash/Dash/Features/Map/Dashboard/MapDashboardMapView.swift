//
//  MapDashboardMapView.swift
//  Dash
//
//  The live map inside a Map dashboard widget (`.large` / `.medium`). It renders
//  the SAME `MapContent` the app-scoped `MapViewModel` already assembles
//  (vehicle indicator, route polyline clipped to the road ahead, destination
//  pin) but swaps the camera for a simple widget-appropriate framing
//  (`MapDashboardCamera`). No `RecenterButton`, no user pan/zoom, no event
//  handling — a widget is a glance, not a control surface.
//
//  It also carries `.mapDashboardObserving(_:)`, which pumps each new fix into
//  the shared `MapFeature` view models so a live navigation session stays
//  current while the dashboard is on screen (see `MapFeature.dashboardObserve`).
//

import DashShared
import SwiftUI

struct MapDashboardMapView: View {

    @ObservedObject var mapViewModel: MapViewModel
    @ObservedObject var navigationViewModel: NavigationViewModel

    /// The feature that owns the state — used only for the fix pump.
    let feature: MapFeature

    @EnvironmentObject private var locationStore: LocationStore

    private var style: MapDashboardCamera.Style {
        navigationViewModel.isActive ? .navigating : .cruising
    }

    /// `MapViewModel.content` re-framed for a widget: same overlays, widget
    /// camera.
    private var widgetContent: MapContent {
        var content = mapViewModel.content
        content.camera = MapDashboardCamera.plan(
            style: style,
            vehicle: content.vehicle.coordinate,
            heading: locationStore.latestPacket?.heading
        )
        return content
    }

    var body: some View {
        mapViewModel.provider
            .makeMapView(content: widgetContent, onEvent: { _ in })
            .allowsHitTesting(false) // a widget map is not pannable / zoomable (M5.2.1)
            .overlay(alignment: .topLeading) {
                if !locationStore.hasFix {
                    Label("Waiting for GPS", systemImage: "location.slash")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
            }
            .mapDashboardObserving(feature)
    }
}

// MARK: - Fix pump for dashboard components

/// Feeds each new `LocationStore` fix into the shared `MapFeature` state while a
/// Map dashboard component is mounted, so the vehicle indicator / camera / route
/// clip / maneuver progress stay live on the dashboard. `MapFeature.dashboardObserve`
/// dedupes by fix timestamp, so several mounted map widgets drive the engine
/// once per fix, not once each.
private struct MapDashboardObservingModifier: ViewModifier {

    let feature: MapFeature
    @EnvironmentObject private var locationStore: LocationStore

    func body(content: Content) -> some View {
        content
            .onAppear { feature.dashboardObserve(locationStore.latestPacket) }
            .onChange(of: locationStore.latestPacket) { _, packet in
                feature.dashboardObserve(packet)
            }
    }
}

extension View {
    func mapDashboardObserving(_ feature: MapFeature) -> some View {
        modifier(MapDashboardObservingModifier(feature: feature))
    }
}
