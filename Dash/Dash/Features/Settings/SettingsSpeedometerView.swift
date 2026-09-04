//
//  SettingsSpeedometerView.swift
//  Dash — Settings feature
//
//  Speedometer's app-settings page (M8.3 §3) — the ONE real per-app setting in
//  this milestone: display unit. A classic Apple "value row → child list with
//  checkmarks" pattern (§3: "a row showing the current selection and a child
//  screen with checkmarks is acceptable").
//
//  Architecture (M8.3 §4): this view touches ONLY `Core/SpeedUnitStore` —
//  never `SpeedometerEngine` or `SpeedometerViewModel`. Settings edits the
//  shared preference; the Speedometer feature's own live views
//  (`SpeedometerGaugeView` / `SpeedometerCompactView`) are what read it and
//  forward it into the engine's presentation. No unit state is persisted here
//  a second time — `SpeedUnitStore` is the only place that happens.
//

import SwiftUI

struct SettingsSpeedometerView: View {

    @EnvironmentObject private var speedUnitStore: SpeedUnitStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SettingsSpeedUnitPickerView()
                } label: {
                    HStack {
                        Text("Speed Unit")
                        Spacer()
                        Text(speedUnitStore.unit.abbreviation)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Choose the unit the Speedometer's digital readout uses.")
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// The child "checkmark list" screen — one row per `SpeedometerUnit`.
struct SettingsSpeedUnitPickerView: View {

    @EnvironmentObject private var speedUnitStore: SpeedUnitStore

    var body: some View {
        List {
            ForEach(SpeedometerUnit.allCases, id: \.self) { unit in
                Button {
                    speedUnitStore.select(unit)
                } label: {
                    HStack {
                        Text(unit.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if unit == speedUnitStore.unit {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityAddTraits(unit == speedUnitStore.unit ? [.isSelected] : [])
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Speed Unit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Speedometer settings") {
    NavigationStack { SettingsSpeedometerView() }
        .environmentObject(SpeedUnitStore())
}

#Preview("Speed unit picker") {
    NavigationStack { SettingsSpeedUnitPickerView() }
        .environmentObject(SpeedUnitStore())
}
#endif
