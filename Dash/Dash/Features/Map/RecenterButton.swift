//
//  RecenterButton.swift
//  Dash
//
//  The small "recenter / resume follow" affordance shown over the map when the
//  user has panned away and vehicle-follow is off (M4.2). Presentational — it
//  holds no state; `DashMapView` decides when to show it and what tapping does.
//  Deliberately NOT inside `GoogleMapProvider` (the provider renders `MapContent`
//  only).
//

import SwiftUI

struct RecenterButton: View {

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemBlue))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter on vehicle")
    }
}

#if DEBUG
#Preview("Recenter button") {
    RecenterButton(action: {})
        .padding()
        .background(Color(white: 0.15))
}
#endif
