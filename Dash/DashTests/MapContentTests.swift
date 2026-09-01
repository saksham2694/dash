//
//  MapContentTests.swift
//  DashTests
//
//  The SDK-neutral map state introduced in the M1 architecture pass: coordinate
//  bounds math, and how `MapViewModel` derives `MapContent` from location + mode.
//  No SDK, no networking.
//

import Foundation
import Testing
@testable import Dash
import DashShared

@Suite("MapCoordinateBounds")
struct MapCoordinateBoundsTests {

    @Test("an empty coordinate list has no bounds")
    func emptyIsNil() {
        #expect(MapCoordinateBounds([]) == nil)
    }

    @Test("a single coordinate makes a degenerate box at that point")
    func singleCoordinate() {
        let point = MapCoordinate(latitude: 12.97, longitude: 77.59)
        let bounds = MapCoordinateBounds([point])
        #expect(bounds?.southWest == point)
        #expect(bounds?.northEast == point)
        #expect(bounds?.center == point)
    }

    @Test("bounds span the min/max latitude and longitude of all points")
    func spansExtremes() {
        let bounds = MapCoordinateBounds([
            MapCoordinate(latitude: 12.0, longitude: 77.5),
            MapCoordinate(latitude: 13.5, longitude: 77.2),
            MapCoordinate(latitude: 12.8, longitude: 78.1),
        ])
        #expect(bounds?.southWest == MapCoordinate(latitude: 12.0, longitude: 77.2))
        #expect(bounds?.northEast == MapCoordinate(latitude: 13.5, longitude: 78.1))
    }

    @Test("centre is the midpoint of the box")
    func centreIsMidpoint() {
        let bounds = MapCoordinateBounds([
            MapCoordinate(latitude: 10, longitude: 20),
            MapCoordinate(latitude: 20, longitude: 40),
        ])
        #expect(bounds?.center == MapCoordinate(latitude: 15, longitude: 30))
    }
}

@MainActor
@Suite("MapViewModel content")
struct MapViewModelContentTests {

    private func packet(latitude: Double, longitude: Double, heading: Double = -1) -> LocationPacket {
        LocationPacket(
            latitude: latitude, longitude: longitude,
            speed: 0, heading: heading,
            timestamp: Date(timeIntervalSince1970: 1_756_700_000)
        )
    }

    @Test("starts cruising with no overlays and a follow camera")
    func initialState() {
        let vm = MapViewModel()
        #expect(vm.mode == .cruising)
        #expect(vm.content.polylines.isEmpty)
        #expect(vm.content.markers.isEmpty)
        #expect(vm.content.camera == .follow(.default))
        #expect(vm.content.vehicle == MapCameraState.default.center)
    }

    @Test("a fix moves the vehicle and the follow camera together")
    func fixUpdatesVehicleAndCamera() {
        let vm = MapViewModel()
        vm.update(with: packet(latitude: 5, longitude: 6))

        #expect(vm.content.vehicle == MapCoordinate(latitude: 5, longitude: 6))
        #expect(vm.content.camera == .follow(vm.camera))
        #expect(vm.camera.latitude == 5)
        #expect(vm.camera.longitude == 6)
    }

    @Test("update(with: nil) leaves content untouched")
    func nilFixIsNoOp() {
        let vm = MapViewModel()
        vm.update(with: packet(latitude: 1, longitude: 2))
        let before = vm.content
        vm.update(with: nil)
        #expect(vm.content == before)
    }

    @Test("follow camera keeps its zoom across fixes")
    func zoomPersists() {
        let vm = MapViewModel()
        vm.update(with: packet(latitude: 1, longitude: 1))
        let zoom = vm.camera.zoom
        vm.update(with: packet(latitude: 2, longitude: 2))
        #expect(vm.camera.zoom == zoom)
    }

    @Test("setMode changes the mode; non-cruising modes still yield a valid follow camera for now")
    func setModeFallsBackToFollow() {
        let vm = MapViewModel()
        vm.update(with: packet(latitude: 9, longitude: 9))

        vm.setMode(.destinationPreview)
        #expect(vm.mode == .destinationPreview)
        #expect(vm.content.camera == .follow(vm.camera))

        vm.setMode(.navigating)
        #expect(vm.mode == .navigating)
        #expect(vm.content.camera == .follow(vm.camera))
    }

    private func destination(
        _ id: String = "dest-1",
        name: String = "Airport",
        lat: Double = 13.2,
        lon: Double = 77.7
    ) -> Destination {
        Destination(
            placeID: id, name: name, address: "Devanahalli",
            coordinate: MapCoordinate(latitude: lat, longitude: lon)
        )
    }

    @Test("selecting a destination drops a pin and enters preview mode")
    func setDestinationDropsPin() {
        let vm = MapViewModel()
        vm.update(with: packet(latitude: 12.0, longitude: 77.0))

        vm.setDestination(destination(name: "Airport"))

        #expect(vm.mode == .destinationPreview)
        #expect(vm.content.markers == [
            MapMarker(id: "dest-1", coordinate: MapCoordinate(latitude: 13.2, longitude: 77.7), title: "Airport")
        ])
    }

    @Test("preview camera frames the vehicle and the destination")
    func previewCameraFitsBoth() {
        let vm = MapViewModel()
        vm.update(with: packet(latitude: 12.0, longitude: 77.0))
        vm.setDestination(destination(lat: 13.2, lon: 77.7))

        let expectedBounds = MapCoordinateBounds([
            MapCoordinate(latitude: 12.0, longitude: 77.0),
            MapCoordinate(latitude: 13.2, longitude: 77.7),
        ])
        #expect(vm.content.camera == .fit(expectedBounds!, padding: MapViewModel.previewPadding))
    }

    @Test("while previewing, a new fix moves the vehicle but not the camera")
    func previewCameraStaysWhileVehicleMoves() {
        let vm = MapViewModel()
        vm.update(with: packet(latitude: 12.0, longitude: 77.0))
        vm.setDestination(destination(lat: 13.2, lon: 77.7))
        let framed = vm.content.camera

        vm.update(with: packet(latitude: 12.5, longitude: 77.3))

        #expect(vm.content.vehicle == MapCoordinate(latitude: 12.5, longitude: 77.3))
        #expect(vm.content.camera == framed)
    }

    @Test("clearing the destination removes the pin and resumes following")
    func clearDestinationResumesFollowing() {
        let vm = MapViewModel()
        vm.update(with: packet(latitude: 12.0, longitude: 77.0))
        vm.setDestination(destination())

        vm.setDestination(nil)

        #expect(vm.mode == .cruising)
        #expect(vm.content.markers.isEmpty)
        #expect(vm.content.camera == .follow(vm.camera))
        #expect(vm.destination == nil)
    }

    @Test("a destination with no name produces a marker without a title")
    func namelessDestinationHasNoTitle() {
        let vm = MapViewModel()
        vm.setDestination(destination(name: ""))
        #expect(vm.content.markers.first?.title == nil)
    }

    @Test("map events are accepted and do not mutate render state yet")
    func eventsAreInert() {
        let vm = MapViewModel()
        vm.update(with: packet(latitude: 3, longitude: 4))
        let before = vm.content

        vm.handle(.tappedMap(MapCoordinate(latitude: 0, longitude: 0)))
        vm.handle(.tappedPOI(MapPOI(placeID: "abc", name: "Cafe", coordinate: MapCoordinate(latitude: 1, longitude: 1))))
        vm.handle(.tappedMarker(id: "dest"))
        vm.handle(.cameraIdle(
            MapCameraPosition(center: MapCoordinate(latitude: 2, longitude: 2), zoom: 15, headingDegrees: 90),
            byUserGesture: true
        ))

        #expect(vm.content == before)
    }
}
