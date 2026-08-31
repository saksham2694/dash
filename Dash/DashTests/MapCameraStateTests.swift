//
//  MapCameraStateTests.swift
//  DashTests
//
//  The pure location -> camera transform behind the map abstraction. No SDK, no
//  networking.
//

import Foundation
import Testing
@testable import Dash
import DashShared

@Suite("MapCameraState")
struct MapCameraStateTests {

    private func packet(
        latitude: Double = 12.9716,
        longitude: Double = 77.5946,
        heading: Double = 90
    ) -> LocationPacket {
        LocationPacket(
            latitude: latitude, longitude: longitude,
            speed: 10, heading: heading,
            timestamp: Date(timeIntervalSince1970: 1_756_700_000)
        )
    }

    @Test("default camera has an unknown heading")
    func defaultHeading() {
        #expect(MapCameraState.default.headingDegrees == nil)
    }

    @Test("following re-centres on the packet and keeps zoom")
    func followingRecentres() {
        let start = MapCameraState(latitude: 0, longitude: 0, headingDegrees: nil, zoom: 17)
        let next = start.following(packet(latitude: 1.5, longitude: 2.5, heading: 45))

        #expect(next.latitude == 1.5)
        #expect(next.longitude == 2.5)
        #expect(next.headingDegrees == 45)
        #expect(next.zoom == 17)
    }

    @Test("a negative (invalid) packet heading becomes nil")
    func invalidHeadingDropped() {
        let next = MapCameraState.default.following(packet(heading: -1))
        #expect(next.headingDegrees == nil)
    }

    @Test("a zero heading is kept (due north, not missing)")
    func zeroHeadingKept() {
        let next = MapCameraState.default.following(packet(heading: 0))
        #expect(next.headingDegrees == 0)
    }
}

@MainActor
@Suite("MapViewModel")
struct MapViewModelTests {

    private func packet(latitude: Double, longitude: Double) -> LocationPacket {
        LocationPacket(
            latitude: latitude, longitude: longitude,
            speed: 0, heading: -1,
            timestamp: Date(timeIntervalSince1970: 1_756_700_000)
        )
    }

    @Test("defaults to the Google Maps provider")
    func defaultProvider() {
        #expect(MapViewModel().provider.id == .googleMaps)
    }

    @Test("update(with:) moves the camera")
    func updateMovesCamera() {
        let vm = MapViewModel()
        vm.update(with: packet(latitude: 5, longitude: 6))

        #expect(vm.camera.latitude == 5)
        #expect(vm.camera.longitude == 6)
    }

    @Test("update(with: nil) leaves the camera unchanged")
    func updateNilIsNoOp() {
        let vm = MapViewModel()
        let before = vm.camera
        vm.update(with: nil)
        #expect(vm.camera == before)
    }
}
