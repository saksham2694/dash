//
//  WeatherLocationSource.swift
//  Dash — Weather feature
//
//  The one seam between the Weather feature and the rest of Dash's location
//  pipeline — mirrors `SpeedometerTelemetry` exactly. The feature never talks
//  to `LocationStore`, the network layer, or introduces its own
//  `CLLocationManager`; it only reads this protocol. Dash provides the
//  conformance (`WeatherLocationSource+LocationStore.swift`); a future
//  standalone Weather app would provide its own.
//
//  Self-contained: only this feature's own `WeatherCoordinate`.
//

import Foundation

/// What the Weather feature needs from its host to know where to fetch
/// weather for.
@MainActor
protocol WeatherLocationSource: AnyObject {

    /// The current coordinate, or `nil` before Dash has ever received a GPS
    /// fix. `WeatherViewModel` stays in its `.unavailable` presentation until
    /// this is non-nil at least once.
    var currentCoordinate: WeatherCoordinate? { get }
}
