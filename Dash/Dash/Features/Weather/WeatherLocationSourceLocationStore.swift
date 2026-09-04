//
//  WeatherLocationSourceLocationStore.swift
//  Dash — Weather feature ↔ Dash bridge
//
//  The ONE file that couples the Weather feature to Dash's location pipeline.
//  Teaches `LocationStore` (the sanctioned single source of truth for received
//  location data) to satisfy `WeatherLocationSource` — mirrors
//  `SpeedometerTelemetryLocationStore.swift` exactly.
//
//  To extract Weather into its own app: delete this file and provide a
//  conformance backed by that app's own location source.
//

import DashShared
import Foundation

extension LocationStore: WeatherLocationSource {

    var currentCoordinate: WeatherCoordinate? {
        latestPacket.map { WeatherCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
