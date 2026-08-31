//
//  MapViewModel.swift
//  Dash
//
//  Drives the active map provider (spec §4). It transforms location that is fed in
//  from outside into `MapCameraState` and holds the provider selection. It does NOT
//  own or duplicate `LocationStore` — no GPS, no networking, no watchdog here.
//

import Combine
import DashShared
import Foundation

@MainActor
final class MapViewModel: ObservableObject {

    /// The active backend. Reassign to switch providers (e.g. from Settings);
    /// nothing else in the dashboard changes.
    @Published var provider: any MapProvider

    /// The camera the map is currently showing. Updated only via `update(with:)`.
    @Published private(set) var camera: MapCameraState

    convenience init(camera: MapCameraState = .default) {
        self.init(provider: GoogleMapProvider(), camera: camera)
    }

    init(provider: any MapProvider, camera: MapCameraState = .default) {
        self.provider = provider
        self.camera = camera
    }

    /// Feed in the latest known location. The caller owns `LocationStore`; this
    /// only re-centres the camera. `nil` (no fix yet) leaves the camera as-is.
    func update(with packet: LocationPacket?) {
        guard let packet else { return }
        camera = camera.following(packet)
    }
}
