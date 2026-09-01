//
//  GooglePlacesConfiguration.swift
//  Dash
//
//  Hands the Google Places SDK for iOS its API key at launch. Uses the *same*
//  build-injected key as the Maps SDK (`GoogleMapsAPIKey` in Info.plist — one key
//  covers every Google Maps Platform API for this bundle). Nothing in source
//  hardcodes it. See `GoogleMapsConfiguration` for the injection chain.
//
//  Requires "Places API (New)" to be enabled on the Google Cloud project and the
//  key's API restrictions to allow it.
//

import Foundation
import GooglePlaces

enum GooglePlacesConfiguration {

    /// Hand the key to the Places SDK. Call once at launch, before any
    /// `GMSPlacesClient` use. Returns `false` (and does nothing) if no key is
    /// configured for this build.
    @discardableResult
    static func bootstrap() -> Bool {
        guard let apiKey = GoogleMapsConfiguration.apiKey else { return false }
        return GMSPlacesClient.provideAPIKey(apiKey)
    }
}
