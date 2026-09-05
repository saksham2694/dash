//
//  MapAppearance.swift
//  Dash
//
//  The map's visual style — independent of `MapProviderID` (which SDK renders
//  the map) and `MapMode` (what the map is currently for). Lives at
//  `Features/` root, alongside `ComponentSize` / `SpeedometerUnit`, because it
//  is cross-cutting vocabulary two features share: Settings offers the picker,
//  the Map feature's `GoogleMapProvider` resolves it into an actual style.
//
//  The persisted preference itself lives in `Core/MapAppearanceStore.swift` —
//  this file only defines the appearance's vocabulary, never touches
//  `UserDefaults`.
//

import Foundation

nonisolated enum MapAppearance: String, CaseIterable, Sendable, Codable {

    case standard
    case gtaSanAndreas

    /// The default until `MapAppearanceStore` has a saved preference.
    static let `default`: MapAppearance = .standard

    /// Label for a Settings picker row.
    var displayName: String {
        switch self {
        case .standard: return "Default"
        case .gtaSanAndreas: return "GTA San Andreas"
        }
    }
}
