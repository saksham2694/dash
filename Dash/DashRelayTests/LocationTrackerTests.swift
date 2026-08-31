//
//  LocationTrackerTests.swift
//  DashRelayTests
//
//  Covers the hardware-free logic in LocationTracker: the CLLocation -> LocationPacket
//  conversion (including CLLocation's negative-means-invalid semantics for speed and
//  course) and the CLLocationManager configuration required by the spec.
//

import CoreLocation
import Foundation
import Testing
@testable import DashRelay
import DashShared

@MainActor
@Suite("LocationTracker")
struct LocationTrackerTests {

    private func location(
        latitude: Double = 12.9716,
        longitude: Double = 77.5946,
        course: CLLocationDirection = 90,
        speed: CLLocationSpeed = 12,
        timestamp: Date = Date(timeIntervalSince1970: 1_756_700_000)
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }

    @Test("maps coordinate, speed, heading and timestamp straight through")
    func mapsAllFields() {
        let ts = Date(timeIntervalSince1970: 1_756_700_123)
        let packet = LocationTracker.packet(
            from: location(latitude: -33.8688, longitude: 151.2093, course: 271.5, speed: 27.3, timestamp: ts)
        )

        #expect(packet.latitude == -33.8688)
        #expect(packet.longitude == 151.2093)
        #expect(packet.speed == 27.3)
        #expect(packet.heading == 271.5)
        #expect(packet.timestamp == ts)
    }

    @Test("keeps speed in m/s without converting or clamping")
    func speedIsRawMetresPerSecond() {
        let packet = LocationTracker.packet(from: location(speed: 10))
        #expect(packet.speed == 10) // not 36 km/h
    }

    @Test("preserves a negative (invalid) speed")
    func invalidSpeedPreserved() {
        let packet = LocationTracker.packet(from: location(speed: -1))
        #expect(packet.speed == -1)
    }

    @Test("preserves a negative (invalid) course")
    func invalidCoursePreserved() {
        let packet = LocationTracker.packet(from: location(course: -1))
        #expect(packet.heading == -1)
    }

    @Test("converted packet survives a JSON round-trip")
    func packetRoundTripsAsJSON() throws {
        let original = LocationTracker.packet(from: location())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(LocationPacket.self, from: try encoder.encode(original))
        #expect(decoded == original)
    }

    @Test("configures CLLocationManager per the background-reliability spec")
    func configuresManager() {
        let manager = CLLocationManager()
        let tracker = LocationTracker(manager: manager)

        #expect(manager.pausesLocationUpdatesAutomatically == false)
        #expect(manager.desiredAccuracy == kCLLocationAccuracyBestForNavigation)
        #expect(manager.activityType == .automotiveNavigation)
        #expect(manager.delegate === tracker)
    }

    @Test("starts with no packet and not tracking")
    func initialState() {
        let tracker = LocationTracker(manager: CLLocationManager())
        #expect(tracker.latestPacket == nil)
        #expect(tracker.isTracking == false)
    }
}
