//
//  GoogleMapStyleResolver.swift
//  Dash
//
//  Resolves a `MapAppearance` into a Google Maps JSON base-map style (the
//  "cloudless" client-side styling mechanism — an array of
//  `{featureType, elementType, stylers}` rules; see
//  https://developers.google.com/maps/documentation/ios-sdk/style-reference).
//  `GoogleMapProvider` is the only caller — it turns the JSON this returns into
//  a `GMSMapStyle` and assigns it to `GMSMapView.mapStyle`.
//
//  Kept as pure data (no GoogleMaps import) so the style itself is
//  unit-testable — valid JSON, resolves to `nil` for `.standard` — without a
//  `GMSMapView`.
//
//  What this can'*t* do: base-map JSON styling only reaches the roads /
//  terrain / water / land / POI / label layers Google exposes through this
//  mechanism. It cannot reskin the built-in compass, restyle individual POI
//  glyphs, or add new POI categories — those stay out of scope here and are
//  handled (if at all) as separate overlays in `GoogleMapProvider`.
//

import Foundation

nonisolated enum GoogleMapStyleResolver {

    /// The JSON style string for `appearance`, or `nil` to use the SDK's
    /// unmodified default style (`GMSMapView.mapStyle = nil`).
    static func styleJSON(for appearance: MapAppearance) -> String? {
        switch appearance {
        case .standard:
            return nil
        case .gtaSanAndreas:
            return gtaSanAndreasStyleJSON
        }
    }

    /// A flat, high-contrast, low-label style in the visual language of the
    /// classic GTA San Andreas radar map: dark olive/forest terrain, flat grey
    /// urban areas, saturated blue water, and cased roads — tan/yellow
    /// highways and white/light-grey local roads over strong dark casings.
    /// Labels are suppressed almost entirely: turn-by-turn guidance in Dash
    /// comes from its own maneuver-card UI (`NavigationViewModel` /
    /// `ManeuverCardView`), never from reading text on the base map, so a
    /// near-textless basemap does not cost real navigability.
    private static let gtaSanAndreasStyleJSON = """
    [
      { "elementType": "geometry", "stylers": [{ "color": "#3a5f3a" }] },
      { "elementType": "labels", "stylers": [{ "visibility": "off" }] },

      { "featureType": "administrative", "elementType": "geometry", "stylers": [{ "visibility": "off" }] },
      { "featureType": "administrative.country", "elementType": "geometry.stroke", "stylers": [{ "visibility": "on" }, { "color": "#16281a" }, { "weight": 1 }] },

      { "featureType": "landscape", "elementType": "geometry.fill", "stylers": [{ "color": "#3a5f3a" }] },
      { "featureType": "landscape.natural", "elementType": "geometry.fill", "stylers": [{ "color": "#3f6b2f" }] },
      { "featureType": "landscape.natural.terrain", "stylers": [{ "visibility": "off" }] },
      { "featureType": "landscape.man_made", "elementType": "geometry.fill", "stylers": [{ "color": "#9b9b93" }] },
      { "featureType": "landscape.man_made", "elementType": "geometry.stroke", "stylers": [{ "color": "#1a1a17" }, { "weight": 0.5 }] },

      { "featureType": "poi", "stylers": [{ "visibility": "off" }] },
      { "featureType": "poi.park", "elementType": "geometry.fill", "stylers": [{ "color": "#355e2b" }] },

      { "featureType": "road", "elementType": "labels", "stylers": [{ "visibility": "off" }] },
      { "featureType": "road", "elementType": "geometry.stroke", "stylers": [{ "color": "#1a1a17" }] },

      { "featureType": "road.highway", "elementType": "geometry.fill", "stylers": [{ "color": "#e8c568" }] },
      { "featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{ "color": "#1a1a17" }, { "weight": 4 }] },

      { "featureType": "road.arterial", "elementType": "geometry.fill", "stylers": [{ "color": "#e0e0d8" }] },
      { "featureType": "road.arterial", "elementType": "geometry.stroke", "stylers": [{ "color": "#1a1a17" }, { "weight": 2 }] },

      { "featureType": "road.local", "elementType": "geometry.fill", "stylers": [{ "color": "#e0e0d8" }] },
      { "featureType": "road.local", "elementType": "geometry.stroke", "stylers": [{ "color": "#1a1a17" }, { "weight": 1 }] },

      { "featureType": "transit", "stylers": [{ "visibility": "off" }] },

      { "featureType": "water", "elementType": "geometry.fill", "stylers": [{ "color": "#0066ff" }] },
      { "featureType": "water", "elementType": "labels", "stylers": [{ "visibility": "off" }] }
    ]
    """
}
