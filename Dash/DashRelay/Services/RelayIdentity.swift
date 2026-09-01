//
//  RelayIdentity.swift
//  DashRelay
//
//  Provides this relay's stable identity for pairing. The iPad needs to recognise
//  "the same iPhone" across launches and networks; the Bonjour service name can't
//  do that (it is hardcoded and identical for every relay). So DashRelay mints a
//  random UUID once, persists it, and publishes it in its Bonjour TXT record via
//  `RelayAdvertisement` (defined in `DashShared`).
//
//  The identity lives for the life of the install. Deleting and reinstalling
//  DashRelay produces a new identity — the iPad would then treat it as a new
//  device and the user re-pairs once. That trade-off is deliberate: it keeps the
//  identity purely local with no account or server.
//

import DashShared
import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum RelayIdentity {

    private static let storageKey = "com.sakshamsharma.DashRelay.relayID"

    /// The advertisement to publish: a persisted UUID plus the device name.
    /// Reads the stored id or creates and saves one on first call.
    static func load(
        defaults: UserDefaults = .standard,
        deviceName: String = RelayIdentity.currentDeviceName
    ) -> RelayAdvertisement {
        let id: String
        if let existing = defaults.string(forKey: storageKey), !existing.isEmpty {
            id = existing
        } else {
            id = UUID().uuidString
            defaults.set(id, forKey: storageKey)
        }
        return RelayAdvertisement(id: id, displayName: deviceName)
    }

    /// The best human-readable name for this device that is available without a
    /// special entitlement. On modern iOS this is often the model name ("iPhone")
    /// rather than the user-set name — good enough as a label; the stable id is
    /// what pairing actually keys on.
    static var currentDeviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }
}
