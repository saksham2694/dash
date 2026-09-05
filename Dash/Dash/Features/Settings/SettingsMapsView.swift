//
//  SettingsMapsView.swift
//  Dash — Settings feature
//
//  Google Maps' app-settings page (M9.1) — the ONE real per-app setting in
//  this milestone: visual appearance. The same classic Apple "value row →
//  child list with checkmarks" pattern `SettingsSpeedometerView` already uses
//  for Speed Unit.
//
//  Architecture: this view touches ONLY `Core/MapAppearanceStore` — never
//  `MapViewModel` or `GoogleMapProvider`. Settings edits the shared
//  preference; the Map feature's own live views (`DashMapView` /
//  `MapDashboardMapView`) are what read it and forward it into the map
//  provider. No appearance state is persisted here a second time —
//  `MapAppearanceStore` is the only place that happens.
//

import SwiftUI

struct SettingsMapsView: View {

    @EnvironmentObject private var mapAppearanceStore: MapAppearanceStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SettingsMapAppearancePickerView()
                } label: {
                    HStack {
                        Text("Map Appearance")
                        Spacer()
                        Text(mapAppearanceStore.appearance.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Choose the visual style Google Maps renders on the dashboard.")
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// The child "checkmark list" screen — one row per `MapAppearance`.
struct SettingsMapAppearancePickerView: View {

    @EnvironmentObject private var mapAppearanceStore: MapAppearanceStore

    var body: some View {
        List {
            ForEach(MapAppearance.allCases, id: \.self) { appearance in
                Button {
                    mapAppearanceStore.select(appearance)
                } label: {
                    HStack {
                        Text(appearance.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if appearance == mapAppearanceStore.appearance {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityAddTraits(appearance == mapAppearanceStore.appearance ? [.isSelected] : [])
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Map Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Maps settings") {
    NavigationStack { SettingsMapsView() }
        .environmentObject(MapAppearanceStore())
}

#Preview("Map appearance picker") {
    NavigationStack { SettingsMapAppearancePickerView() }
        .environmentObject(MapAppearanceStore())
}
#endif
