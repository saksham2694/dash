//
//  VehicleIndicatorTests.swift
//  DashTests
//
//  M4.1 — the SDK-neutral current-location / vehicle indicator: how a relayed
//  `LocationPacket` maps to a `VehicleIndicator` (position + validated heading),
//  and the pure dot-vs-pointer rendering decision `GoogleMapProvider` makes from
//  it. No SDK, no networking, no live Google services.
//

import Foundation
import Testing
@testable import Dash
import DashShared

private func packet(
    lat: Double = 12.9,
    lon: Double = 77.6,
    heading: Double = 90
) -> LocationPacket {
    LocationPacket(
        latitude: lat, longitude: lon,
        speed: 8, heading: heading,
        timestamp: Date(timeIntervalSince1970: 1_756_700_000)
    )
}

@Suite("VehicleIndicator")
struct VehicleIndicatorTests {

    @Test("carries the packet coordinate")
    func coordinate() {
        let v = VehicleIndicator(packet(lat: 30.73, lon: 76.80))
        #expect(v.coordinate == MapCoordinate(latitude: 30.73, longitude: 76.80))
    }

    @Test("a usable heading is kept as the orientation")
    func usableHeadingKept() {
        #expect(VehicleIndicator(packet(heading: 137.5)).headingDegrees == 137.5)
    }

    @Test("a zero heading is kept (due north, not missing)")
    func zeroHeadingKept() {
        #expect(VehicleIndicator(packet(heading: 0)).headingDegrees == 0)
    }

    @Test("a negative heading (invalid fix) drops to no orientation")
    func negativeHeadingDropped() {
        #expect(VehicleIndicator(packet(heading: -1)).headingDegrees == nil)
    }

    @Test("a NaN heading drops to no orientation rather than propagating")
    func nanHeadingDropped() {
        #expect(VehicleIndicator(packet(heading: .nan)).headingDegrees == nil)
    }

    @Test("the memberwise initialiser defaults to no heading")
    func memberwiseDefault() {
        let v = VehicleIndicator(coordinate: MapCoordinate(latitude: 1, longitude: 2))
        #expect(v.headingDegrees == nil)
    }
}

@Suite("GoogleMapProvider.vehicleStyle")
struct GoogleMapVehicleStyleTests {

    @Test("no heading → a plain location dot")
    func noHeadingIsDot() {
        let style = GoogleMapProvider.vehicleStyle(
            for: VehicleIndicator(coordinate: MapCoordinate(latitude: 1, longitude: 2))
        )
        #expect(style == .locationDot)
    }

    @Test("a heading → a directional pointer rotated to that bearing")
    func headingIsRotatedPointer() {
        let style = GoogleMapProvider.vehicleStyle(
            for: VehicleIndicator(coordinate: MapCoordinate(latitude: 1, longitude: 2), headingDegrees: 215)
        )
        #expect(style == .directionalPointer(rotationDegrees: 215))
    }

    @Test("heading 0 still yields a pointer (facing north), not a dot")
    func zeroHeadingIsPointer() {
        let style = GoogleMapProvider.vehicleStyle(
            for: VehicleIndicator(coordinate: MapCoordinate(latitude: 1, longitude: 2), headingDegrees: 0)
        )
        #expect(style == .directionalPointer(rotationDegrees: 0))
    }
}
