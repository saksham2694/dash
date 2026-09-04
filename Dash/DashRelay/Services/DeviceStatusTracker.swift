//
//  DeviceStatusTracker.swift
//  DashRelay
//
//  Reads the iPhone's own battery via `UIDevice` and turns it into a
//  `DeviceStatusPacket` for the relay to broadcast. Analogous to
//  `LocationTracker` but for device status rather than GPS — it does not know
//  about networking.
//
//  Responsible battery monitoring: `start()` enables `UIDevice` battery
//  monitoring; `stop()` disables it. Updates are **event-driven** — it observes
//  `UIDevice.batteryLevelDidChangeNotification` / `batteryStateDidChangeNotification`
//  (iOS posts these only on a meaningful change) and emits a packet only when the
//  whole-percent bucket or the charging state actually changed. No polling loop.
//

import Combine
import Foundation
import UIKit
import DashShared

/// The `UIDevice` surface this tracker needs — injected so tests can drive it
/// without real hardware.
@MainActor
protocol BatteryReadingDevice: AnyObject {
    var isBatteryMonitoringEnabled: Bool { get set }
    var batteryLevel: Float { get }
    var batteryState: UIDevice.BatteryState { get }
}

extension UIDevice: BatteryReadingDevice {}

@MainActor
final class DeviceStatusTracker: ObservableObject {

    /// The most recent status emitted (also handed to a late-joining client by
    /// the broadcaster via its own cache).
    @Published private(set) var latest: DeviceStatusPacket?

    /// Fired only when the value / state meaningfully changes. Wired to the
    /// broadcaster by `RelaySessionController`.
    var onStatusChange: ((DeviceStatusPacket) -> Void)?

    private let device: BatteryReadingDevice
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private var observers: [NSObjectProtocol] = []
    private var isRunning = false

    /// The last (bucket, state) we emitted — used to suppress no-op updates.
    private var lastEmitted: (percent: Int?, state: BatteryState)?

    init(
        device: BatteryReadingDevice = UIDevice.current,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.device = device
        self.notificationCenter = notificationCenter
        self.now = now
    }

    deinit {
        for observer in observers { notificationCenter.removeObserver(observer) }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        device.isBatteryMonitoringEnabled = true

        observers = [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification,
        ].map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }

        // Emit the current value immediately so a dashboard doesn't wait for the
        // first change.
        lastEmitted = nil
        refresh()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for observer in observers { notificationCenter.removeObserver(observer) }
        observers.removeAll()
        device.isBatteryMonitoringEnabled = false
    }

    // MARK: - Reading

    /// Re-read the device and emit a packet if the whole-percent bucket or the
    /// charging state changed since the last emission. Exposed for tests.
    func refresh() {
        let status = currentStatus()
        let key = (status.batteryPercent, status.batteryState)
        if let last = lastEmitted, last.percent == key.0, last.state == key.1 { return }
        lastEmitted = key
        latest = status
        onStatusChange?(status)
    }

    private func currentStatus() -> DeviceStatusPacket {
        let raw = device.batteryLevel   // -1 when unknown / monitoring off
        let level: Double? = raw >= 0 ? Double(raw) : nil
        return DeviceStatusPacket(
            batteryLevel: level,
            batteryState: Self.map(device.batteryState),
            timestamp: now()
        )
    }

    /// Pure mapping from `UIDevice.BatteryState` to the SDK-neutral wire enum.
    static func map(_ state: UIDevice.BatteryState) -> BatteryState {
        switch state {
        case .charging:  return .charging
        case .full:      return .full
        case .unplugged: return .unplugged
        case .unknown:   return .unknown
        @unknown default: return .unknown
        }
    }
}
