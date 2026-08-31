//
//  GoogleMapsConfiguration.swift
//  Dash
//
//  Supplies the Google Maps SDK for iOS key. The key is injected at build time
//  through:  Dash/Config/GoogleMapsService.xcconfig  ->  build setting
//  GOOGLE_MAPS_API_KEY  ->  Info.plist key "GoogleMapsAPIKey" ($(GOOGLE_MAPS_API_KEY))
//  and read back here at runtime. Nothing in source hardcodes the key.
//
//  No map UI is wired up yet — the map bootstrap will call `bootstrap()` once,
//  before creating any `GMSMapView`.
//

import Foundation
import GoogleMaps

enum GoogleMapsConfiguration {

    /// Info.plist key that carries the build-injected API key.
    static let infoPlistKey = "GoogleMapsAPIKey"

    /// The configured key, or `nil` when it wasn't supplied for this build
    /// (e.g. a fresh checkout before `GoogleMapsService.xcconfig` is filled in).
    static var apiKey: String? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return value
    }

    /// Hand the key to the SDK. Call once at launch, before any map view exists.
    /// Returns `false` (and does nothing) if no key is configured.
    @discardableResult
    static func bootstrap() -> Bool {
        guard let apiKey else { return false }
        GMSServices.provideAPIKey(apiKey)
        return true
    }
}
