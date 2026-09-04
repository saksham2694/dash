//
//  DeviceStatusTrackerTests.swift
//  DashRelayTests
//
//  `DeviceStatusTracker` (M5.7) — reads the iPhone battery via an injected
//  `BatteryReadingDevice` and emits a `DeviceStatusPacket` only on a meaningful
//  change. No real hardware, no notifications — `refresh()` is driven directly.
//

import Foundation
import Testing
import UIKit
@testable import DashRelay
import DashShared

@MainActor
final class FakeBatteryDevice: BatteryReadingDevice {
    var isBatteryMonitoringEnabled = false
    var batteryLevel: Float = 0.5
    var batteryState: UIDevice.BatteryState = .unplugged
}

@MainActor
@Suite("DeviceStatusTracker")
struct DeviceStatusTrackerTests {

    private func makeSUT() -> (DeviceStatusTracker, FakeBatteryDevice, Box) {
        let device = FakeBatteryDevice()
        let box = Box()
        let tracker = DeviceStatusTracker(
            device: device,
            notificationCenter: NotificationCenter(),
            now: { Date(timeIntervalSince1970: 0) }
        )
        tracker.onStatusChange = { box.emitted.append($0) }
        return (tracker, device, box)
    }

    final class Box { var emitted: [DeviceStatusPacket] = [] }

    @Test("start emits the current battery value immediately and enables monitoring")
    func startEmitsInitial() {
        let (tracker, device, box) = makeSUT()
        device.batteryLevel = 0.63
        device.batteryState = .unplugged

        tracker.start()

        #expect(device.isBatteryMonitoringEnabled)
        #expect(box.emitted.count == 1)
        #expect(box.emitted.first?.batteryPercent == 63)
        #expect(box.emitted.first?.batteryState == .unplugged)
    }

    @Test("stop disables monitoring")
    func stopDisablesMonitoring() {
        let (tracker, device, _) = makeSUT()
        tracker.start()
        tracker.stop()
        #expect(device.isBatteryMonitoringEnabled == false)
    }

    @Test("an unchanged reading is not re-emitted")
    func dedupesUnchanged() {
        let (tracker, _, box) = makeSUT()
        tracker.start()
        tracker.refresh()
        tracker.refresh()
        #expect(box.emitted.count == 1)
    }

    @Test("a whole-percent change emits; a sub-percent wobble does not")
    func emitsOnPercentChange() {
        let (tracker, device, box) = makeSUT()
        device.batteryLevel = 0.50
        tracker.start()                       // emits 50%

        device.batteryLevel = 0.502           // still 50%
        tracker.refresh()
        #expect(box.emitted.count == 1)

        device.batteryLevel = 0.49            // now 49%
        tracker.refresh()
        #expect(box.emitted.count == 2)
        #expect(box.emitted.last?.batteryPercent == 49)
    }

    @Test("a charging-state change emits even at the same percentage")
    func emitsOnStateChange() {
        let (tracker, device, box) = makeSUT()
        device.batteryLevel = 0.80
        device.batteryState = .unplugged
        tracker.start()

        device.batteryState = .charging
        tracker.refresh()

        #expect(box.emitted.count == 2)
        #expect(box.emitted.last?.batteryState == .charging)
    }

    @Test("an unknown battery level (-1) becomes nil")
    func unknownLevel() {
        let (tracker, device, box) = makeSUT()
        device.batteryLevel = -1
        device.batteryState = .unknown
        tracker.start()
        #expect(box.emitted.first?.batteryLevel == nil)
        #expect(box.emitted.first?.batteryState == .unknown)
    }

    @Test("UIDevice.BatteryState maps to the wire enum")
    func stateMapping() {
        #expect(DeviceStatusTracker.map(.charging) == .charging)
        #expect(DeviceStatusTracker.map(.full) == .full)
        #expect(DeviceStatusTracker.map(.unplugged) == .unplugged)
        #expect(DeviceStatusTracker.map(.unknown) == .unknown)
    }
}
