//
//  WeatherCoordinate.swift
//  Dash — Weather feature
//
//  A minimal, SDK-neutral coordinate — the feature's own vocabulary rather
//  than reaching for `CoreLocation.CLLocationCoordinate2D` outside the one
//  provider file that actually needs it. `distance(to:)` is pure haversine
//  maths, used only by `WeatherRefreshPolicy` to decide whether the car has
//  moved far enough to justify an early re-fetch.
//

import Foundation

nonisolated struct WeatherCoordinate: Equatable, Sendable {

    var latitude: Double
    var longitude: Double

    /// Great-circle distance to `other`, in metres.
    func distance(to other: WeatherCoordinate) -> Double {
        let earthRadiusMetres = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
        return earthRadiusMetres * c
    }
}
