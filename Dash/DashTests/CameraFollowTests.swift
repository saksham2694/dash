//
//  CameraFollowTests.swift
//  DashTests
//
//  M4.2 — vehicle-follow state, user-gesture handling, recenter, and the
//  navigation camera plan. Pure `MapViewModel` logic plus the SDK-free
//  `GoogleMapProvider.UserGestureLatch`. No SDK, no networking.
//

import Foundation
import Testing
@testable import Dash
import DashShared

@MainActor
private func fix(_ lat: Double, _ lon: Double, heading: Double = 90) -> LocationPacket {
    LocationPacket(latitude: lat, longitude: lon, speed: 12, heading: heading,
                   timestamp: Date(timeIntervalSince1970: 1_756_700_000))
}

@MainActor
private func userPan(to lat: Double, _ lon: Double, zoom: Double = 16) -> MapEvent {
    .cameraIdle(
        MapCameraPosition(center: MapCoordinate(latitude: lat, longitude: lon),
                          zoom: zoom, headingDegrees: 0),
        byUserGesture: true
    )
}

/// A user gesture that barely moved the camera — the provider reports every
/// real gesture as user-driven regardless of size (M4.2, no threshold).
@MainActor
private func tinyUserGesture(around lat: Double, _ lon: Double, zoom: Double = 16) -> MapEvent {
    .cameraIdle(
        MapCameraPosition(center: MapCoordinate(latitude: lat + 0.000_002, longitude: lon + 0.000_002),
                          zoom: zoom + 0.01, headingDegrees: 0),
        byUserGesture: true
    )
}

@MainActor
private func navPlan(_ camera: MapCameraState) -> MapCameraPlan {
    .navigation(camera,
                pitchDegrees: MapViewModel.navigationPitchDegrees,
                vehicleVerticalAnchor: MapViewModel.navigationVehicleAnchor)
}

// MARK: - Cruising follow

@MainActor
@Suite("Camera follow — cruising")
struct CruisingFollowTests {

    @Test("follow is on by default and the camera tracks the vehicle on each fix")
    func followsByDefault() {
        let vm = MapViewModel()
        vm.update(with: fix(1, 1))
        #expect(vm.content.camera == .follow(vm.camera))
        vm.update(with: fix(2, 3))
        #expect(vm.content.camera == .follow(vm.camera))
        #expect(vm.camera.latitude == 2)
        #expect(vm.camera.longitude == 3)
    }

    @Test("a meaningful user pan turns follow off; then a fix moves the vehicle but not the camera")
    func userPanDisablesFollow() {
        let vm = MapViewModel()
        vm.update(with: fix(10, 10))
        let frozen = vm.content.camera

        vm.handle(userPan(to: 20, 20))
        #expect(vm.followsVehicle == false)
        #expect(vm.showsRecenterButton)

        vm.update(with: fix(11, 11))
        #expect(vm.content.vehicle.coordinate == MapCoordinate(latitude: 11, longitude: 11))
        #expect(vm.content.camera == frozen) // camera did NOT move with the vehicle
    }

    @Test("even a tiny user pan/zoom gesture turns follow off")
    func smallUserGestureDisablesFollow() {
        let vm = MapViewModel()
        vm.update(with: fix(10, 10))
        let frozen = vm.content.camera

        vm.handle(tinyUserGesture(around: 10, 10))
        #expect(vm.followsVehicle == false)
        #expect(vm.showsRecenterButton)

        vm.update(with: fix(10.5, 10.5))
        #expect(vm.content.vehicle.coordinate == MapCoordinate(latitude: 10.5, longitude: 10.5))
        #expect(vm.content.camera == frozen) // camera stayed put
    }

    @Test("a programmatic camera-idle never disables follow (no feedback loop)")
    func programmaticIdleKeepsFollow() {
        let vm = MapViewModel()
        vm.update(with: fix(10, 10))
        vm.handle(.cameraIdle(
            MapCameraPosition(center: MapCoordinate(latitude: 99, longitude: 99), zoom: 16, headingDegrees: 0),
            byUserGesture: false
        ))
        #expect(vm.followsVehicle)
    }

    @Test("recenter re-enables follow and snaps the camera back to the vehicle")
    func recenterRestoresFollow() {
        let vm = MapViewModel()
        vm.update(with: fix(10, 10))
        vm.handle(userPan(to: 40, 40, zoom: 12))
        #expect(vm.followsVehicle == false)

        vm.recenter()

        #expect(vm.followsVehicle)
        #expect(vm.showsRecenterButton == false)
        #expect(vm.content.camera == .follow(vm.camera))
        // The camera the recenter snaps to is the vehicle's position, at the
        // zoom the user left the map at.
        #expect(vm.camera.latitude == 10)
        #expect(vm.camera.zoom == 12)
    }

    @Test("with follow off, recenter uses the latest vehicle position, not the pan target")
    func recenterFollowsLatestFix() {
        let vm = MapViewModel()
        vm.update(with: fix(10, 10))
        vm.handle(userPan(to: 40, 40))
        vm.update(with: fix(12, 13)) // vehicle keeps moving while follow is off
        #expect(vm.content.camera != .follow(vm.camera)) // still frozen

        vm.recenter()
        #expect(vm.camera.latitude == 12)
        #expect(vm.camera.longitude == 13)
    }

    @Test("choosing then clearing a destination re-arms follow")
    func modeChangeReArmsFollow() {
        let vm = MapViewModel()
        vm.update(with: fix(10, 10))
        vm.handle(userPan(to: 40, 40))
        #expect(vm.followsVehicle == false)

        vm.setDestination(Destination(placeID: "d", name: "X", address: nil,
                                      coordinate: MapCoordinate(latitude: 13, longitude: 14)))
        #expect(vm.followsVehicle) // re-armed (dormant in preview)

        vm.setDestination(nil)
        #expect(vm.mode == .cruising)
        #expect(vm.followsVehicle)
        #expect(vm.content.camera == .follow(vm.camera))
    }
}

// MARK: - Destination preview (M3 must be unchanged)

@MainActor
@Suite("Camera follow — destination preview unchanged")
struct PreviewUnchangedTests {

    private func destination() -> Destination {
        Destination(placeID: "d", name: "Airport", address: nil,
                    coordinate: MapCoordinate(latitude: 13.2, longitude: 77.7))
    }

    @Test("preview is a one-shot fit and a later fix never refits or moves it")
    func previewIsOneShot() {
        let vm = MapViewModel()
        vm.update(with: fix(12.0, 77.0))
        vm.setDestination(destination())

        let framed = vm.content.camera
        if case .fit = framed {} else { Issue.record("expected a .fit preview camera") }

        vm.update(with: fix(12.4, 77.2))
        #expect(vm.content.camera == framed)
        #expect(vm.content.vehicle.coordinate == MapCoordinate(latitude: 12.4, longitude: 77.2))
    }

    @Test("a user pan while previewing does not disable follow / show the recenter button")
    func previewPanDoesNotDisableFollow() {
        let vm = MapViewModel()
        vm.update(with: fix(12.0, 77.0))
        vm.setDestination(destination())

        vm.handle(userPan(to: 30, 30))

        #expect(vm.followsVehicle)          // still armed for when preview ends
        #expect(vm.showsRecenterButton == false)
    }

    @Test("recenter is a no-op while previewing")
    func recenterNoOpInPreview() {
        let vm = MapViewModel()
        vm.update(with: fix(12.0, 77.0))
        vm.setDestination(destination())
        let framed = vm.content.camera

        vm.recenter()
        #expect(vm.content.camera == framed)
    }
}

// MARK: - Navigating camera

@MainActor
@Suite("Camera follow — navigating")
struct NavigatingCameraTests {

    @Test("entering .navigating uses the navigation camera plan")
    func entersNavigationPlan() {
        let vm = MapViewModel()
        vm.update(with: fix(1, 1, heading: 45))
        vm.setMode(.navigating)
        #expect(vm.content.camera == navPlan(vm.camera))
    }

    @Test("while navigating and following, each fix updates the navigation camera")
    func navigatingFollowsVehicle() {
        let vm = MapViewModel()
        vm.setMode(.navigating)
        vm.update(with: fix(5, 6, heading: 120))
        #expect(vm.content.camera == navPlan(vm.camera))
        #expect(vm.camera.headingDegrees == 120)
    }

    @Test("while navigating with follow off, a fix moves the vehicle but not the camera")
    func navigatingRespectsFollowOff() {
        let vm = MapViewModel()
        vm.setMode(.navigating)
        vm.update(with: fix(5, 6))
        let frozen = vm.content.camera

        vm.handle(userPan(to: 40, 40))
        #expect(vm.followsVehicle == false)

        vm.update(with: fix(7, 8))
        #expect(vm.content.vehicle.coordinate == MapCoordinate(latitude: 7, longitude: 8))
        #expect(vm.content.camera == frozen)
    }

    @Test("recenter while navigating snaps back with the navigation plan")
    func recenterUsesNavigationPlan() {
        let vm = MapViewModel()
        vm.setMode(.navigating)
        vm.update(with: fix(5, 6))
        vm.handle(userPan(to: 40, 40))

        vm.recenter()
        #expect(vm.content.camera == navPlan(vm.camera))
    }

    @Test("the navigation plan tilts the camera and anchors the vehicle a little below centre")
    func navigationPlanShape() {
        #expect(MapViewModel.navigationPitchDegrees > 0)
        // Below centre (> 0.5) but not pushed hard down / up.
        #expect(MapViewModel.navigationVehicleAnchor > 0.5)
        #expect(MapViewModel.navigationVehicleAnchor < 0.7)
    }
}

// MARK: - GoogleMapProvider.UserGestureLatch (SDK-free helper)

@Suite("GoogleMapProvider.UserGestureLatch")
struct UserGestureLatchTests {

    @Test("a fresh latch is not user-driven")
    func startsClear() {
        let latch = GoogleMapProvider.UserGestureLatch()
        #expect(latch.isUserDriven == false)
    }

    @Test("a gesture move latches user-driven on until idle consumes it")
    func gestureLatches() {
        var latch = GoogleMapProvider.UserGestureLatch()
        latch.willMove(byGesture: true)
        #expect(latch.isUserDriven)

        let reported = latch.consumeOnIdle()
        #expect(reported)                     // reported to the view model
        #expect(latch.isUserDriven == false)  // and cleared for the next move
    }

    @Test("a programmatic move alone is never user-driven")
    func programmaticMoveIsNotUser() {
        var latch = GoogleMapProvider.UserGestureLatch()
        latch.willMove(byGesture: false)
        let reported = latch.consumeOnIdle()
        #expect(reported == false)
    }

    @Test("a programmatic move interleaved with a gesture does not clear the latch")
    func programmaticMoveDoesNotUnlatch() {
        var latch = GoogleMapProvider.UserGestureLatch()
        latch.willMove(byGesture: true)   // user starts dragging
        latch.willMove(byGesture: false)  // a follow animation fires mid-drag
        let reported = latch.consumeOnIdle()
        #expect(reported)                 // still counts as the user's move
    }

    @Test("the latch does not persist across separate idle events")
    func doesNotLeakToNextMove() {
        var latch = GoogleMapProvider.UserGestureLatch()
        latch.willMove(byGesture: true)
        _ = latch.consumeOnIdle()

        latch.willMove(byGesture: false)  // a later purely programmatic move
        let reported = latch.consumeOnIdle()
        #expect(reported == false)
    }
}
