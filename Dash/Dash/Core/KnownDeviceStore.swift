//
//  KnownDeviceStore.swift
//  Dash
//
//  Pairing / known-device state — conceptually separate from the *current*
//  connection (`ConnectionCoordinator`). A "known device" is a DashRelay this
//  iPad has been told to remember.
//
//  Identity: the relay's **stable id** from its Bonjour TXT record
//  (`RelayAdvertisement.id`), not the Bonjour service name. The service name is
//  identical for every relay and can be renamed by iOS on a collision; the id is
//  minted once per DashRelay install and never changes. See PROJECT_STATUS.md
//  ("device-identity decision").
//
//  This type is storage only — it never touches the network. `ConnectionCoordinator`
//  reads it to decide which relay to prefer, and writes to it (via `remember` /
//  `forget`) when the user pairs or forgets a device. The list is kept so the
//  design extends to multiple known devices; today `pairedRelay` treats the first
//  as "the" paired one.
//

import Combine
import Foundation

/// A DashRelay instance this iPad remembers.
struct KnownRelay: Codable, Equatable, Identifiable {
    /// Stable relay identity (Bonjour TXT `rid`). Matches `DiscoveredRelay.id`.
    let id: String
    /// Human-readable device name, refreshed from the advertisement on re-pair.
    var displayName: String
}

/// Injectable seam for tests.
@MainActor
protocol KnownDeviceStoring: AnyObject {
    var knownDevices: [KnownRelay] { get }
    func remember(_ device: KnownRelay)
    func forget(_ device: KnownRelay)
    func forgetAll()
    func isKnown(id: String) -> Bool
}

extension KnownDeviceStoring {
    /// The relay Dash currently treats as paired. With multiple known devices the
    /// first remembered wins; a chooser among known devices is future work.
    var pairedRelay: KnownRelay? { knownDevices.first }
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

    func isKnown(id: String) -> Bool {
        knownDevices.contains { $0.id == id }
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
