//
//  KnownDeviceStore.swift
//  Dash
//
//  Pairing / known-device state — conceptually separate from the *current*
//  connection (`ConnectionCoordinator`). A "known device" is a DashRelay this
//  iPad has been told to remember, identified by its Bonjour service name
//  (spec §4: "remember the choice ... by Bonjour service name").
//
//  What exists today: durable storage for a list of known devices, with
//  add / remove / list, ready for multiple devices.
//
//  What does NOT exist yet: any flow that decides *when* to remember a device
//  (a pairing UI / "pair on connect"), a "Forget" affordance in the UI, or the
//  connection layer filtering to known devices only. Those are the remaining
//  pairing work — see PROJECT_STATUS.md.
//

import Combine
import Foundation

/// A DashRelay instance this iPad remembers.
struct KnownRelay: Codable, Equatable, Identifiable {
    /// Stable identity = the Bonjour service name.
    var id: String { bonjourServiceName }
    let bonjourServiceName: String
    var displayName: String
}

/// Injectable seam for tests.
@MainActor
protocol KnownDeviceStoring: AnyObject {
    var knownDevices: [KnownRelay] { get }
    func remember(_ device: KnownRelay)
    func forget(_ device: KnownRelay)
    func forgetAll()
    func isKnown(bonjourServiceName: String) -> Bool
}

@MainActor
final class KnownDeviceStore: ObservableObject, KnownDeviceStoring {

    @Published private(set) var knownDevices: [KnownRelay] = []

    private let defaults: UserDefaults
    private let storageKey = "com.sakshamsharma.Dash.knownDevices"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func remember(_ device: KnownRelay) {
        if let index = knownDevices.firstIndex(where: { $0.id == device.id }) {
            knownDevices[index] = device
        } else {
            knownDevices.append(device)
        }
        save()
    }

    func forget(_ device: KnownRelay) {
        knownDevices.removeAll { $0.id == device.id }
        save()
    }

    func forgetAll() {
        knownDevices.removeAll()
        save()
    }

    func isKnown(bonjourServiceName: String) -> Bool {
        knownDevices.contains { $0.bonjourServiceName == bonjourServiceName }
    }

    // MARK: - Persistence

    private func load() {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([KnownRelay].self, from: data)
        else {
            knownDevices = []
            return
        }
        knownDevices = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(knownDevices) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
