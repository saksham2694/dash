//
//  WeatherService.swift
//  Dash — Weather feature
//
//  The provider seam — mirrors `MapProvider` / `PlaceSearchService`'s
//  philosophy (M8.4 §2): `WeatherViewModel` depends on this protocol, never on
//  WeatherKit directly, so a future alternate provider could substitute in
//  behind it without touching anything else in the feature. `WeatherKitService`
//  is the one production conformance.
//

import Foundation

protocol WeatherService: Sendable {

    /// Fetch a full snapshot for a coordinate — current conditions, today's
    /// high/low, and roughly the next 6 hours. Throws on any failure
    /// (network, denied entitlement, decoding); `WeatherViewModel` turns that
    /// into a normal `.failed` / `.stale` presentation — this protocol never
    /// promises a fallback value.
    func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot
}
