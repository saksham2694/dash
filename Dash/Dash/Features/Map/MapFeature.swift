//
//  MapFeature.swift
//  Dash
//
//  The Map feature's adapter to the shell (M5.0). This is the *only* bridge
//  between `Shell/` and the existing Map code: it wraps `ContentView` (the Map
//  composition root) unchanged.
//
//  Deliberately thin. Hoisting `MapViewModel` / `RouteViewModel` /
//  `NavigationViewModel` / … out of `ContentView` into this type — so a
//  navigation session survives leaving and returning to the Map — is M5.1, not
//  this milestone.
//

import SwiftUI

@MainActor
final class MapFeature: DashFeature {

    /// Stable id — used by the sidebar, Home, and (later) dashboard placements.
    static let id: FeatureID = "maps"

    let manifest = FeatureManifest(
        id: MapFeature.id,
        title: "Maps",
        symbolName: "map.fill",
        supportedSizes: [.compact, .medium, .large, .full],
        defaultSize: .large
    )

    /// The existing full-screen Map experience, untouched.
    func makeFullScreenView() -> AnyView {
        AnyView(ContentView())
    }

    /// Dashboard widgets are M5.2 — every widget size shows a placeholder for
    /// now. The real full-screen Map is `makeFullScreenView()`.
    func makeComponentView(size: ComponentSize) -> AnyView {
        AnyView(MapComponentPlaceholder(size: size))
    }
}

/// Temporary stand-in for the Map dashboard widget (M5.2 replaces it with a
/// real reduced-map / maneuver presentation).
private struct MapComponentPlaceholder: View {
    let size: ComponentSize

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "map.fill").font(.title2)
            Text("Maps").font(.headline)
            Text("\(size.rawValue) widget — M5.2")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
