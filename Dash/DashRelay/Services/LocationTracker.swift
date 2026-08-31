//
//  LocationTracker.swift
//  DashRelay
//
//  Wraps CLLocationManager: acquires GPS fixes from the iPhone and converts each
//  one into a DashShared.LocationPacket. It is deliberately the *only* job of this
//  type — it does not know about networking or Bonjour. A consumer (the
//  broadcaster, added later) plugs into `onPacket` to do something with each fix.
//

import Combine
import CoreLocation
import DashShared
import Foundation

@MainActor
final class LocationTracker: NSObject, ObservableObject {

    /// Latest authorization state, mirrored for the UI.
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    /// Whether `CLLocationManager` is currently delivering updates.
    @Published private(set) var isTracking = false

    /// The most recent converted fix, for display in `StatusView`.
    @Published private(set) var latestPacket: LocationPacket?

    /// Invoked synchronously for every new fix, from inside the Core Location
    /// delegate callback. Per the spec, the network send must happen here — on
    /// the GPS-fix wake-up — not on a separate timer. Wired up by the broadcaster.
    var onPacket: ((LocationPacket) -> Void)?

    private let manager: CLLocationManager

    /// Whether the owner (the relay session) currently wants location updates.
    /// Only `start()` / `stop()` change this. Authorization callbacks check it so
    /// a permission change can never revive GPS after a deliberate `stop()`.
    private var wantsTracking = false

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        // Don't let iOS pause updates when it thinks we've stopped (e.g. at a red
        // light) — the dashboard should keep reading zero speed, not go stale.
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Ask for permission if needed, otherwise start streaming immediately.
    func start() {
        wantsTracking = true
        switch manager.authorizationStatus {
        case .notDetermined:
            // "Always" so relaying continues once backgrounded / screen-locked.
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func stop() {
        wantsTracking = false
        manager.stopUpdatingLocation()
        isTracking = false
    }

    private func beginUpdates() {
        // Respect a deliberate stop even if a late authorization callback lands.
        guard wantsTracking else { return }
        // Only legal with (at least) When-In-Use authorization and the "location"
        // background mode in Info.plist; guard on Always so we never trip the
        // runtime exception with a lesser grant.
        if manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.startUpdatingLocation()
        isTracking = true
    }

    /// Pure conversion from a Core Location fix to the shared wire model.
    ///
    /// `speed` and `heading` keep `CLLocation`'s raw semantics: speed is in
    /// metres per second and `course` is degrees clockwise from true north, and
    /// either is **negative when the fix can't determine it**. Consumers on the
    /// iPad side decide how to present that (km/h conversion, smoothing, hiding
    /// an invalid heading) — the relay does not massage the data.
    static func packet(from location: CLLocation) -> LocationPacket {
        LocationPacket(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speed: location.speed,
            heading: location.course,
            timestamp: location.timestamp
        )
    }
}

extension LocationTracker: @preconcurrency CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates() // no-ops unless the session wants tracking
        case .denied, .restricted:
            // Stop delivering, but don't clear `wantsTracking` — if the user
            // re-grants permission while the session is still active, resume.
            manager.stopUpdatingLocation()
            isTracking = false
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let packet = Self.packet(from: location)
        latestPacket = packet
        // Hand the fix straight to the consumer, in-callback.
        onPacket?(packet)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // `.locationUnknown` is transient — Core Location keeps trying. Nothing
        // to do here; the iPad-side watchdog covers a sustained gap.
    }
}
