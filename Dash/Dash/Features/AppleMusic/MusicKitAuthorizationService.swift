//
//  MusicKitAuthorizationService.swift
//  Dash — Apple Music feature
//
//  The production `MusicAuthorizationService` — Apple `MusicKit`. Requires
//  `NSAppleMusicUsageDescription` (added to `Info.plist`) and, per Apple
//  Developer Portal + Xcode setup, the "MusicKit" capability on the App ID
//  (see PROJECT_STATUS.md's M9.0 entry for the exact manual step — the same
//  pattern WeatherKit needed).
//

import MusicKit

struct MusicKitAuthorizationService: MusicAuthorizationService {

    var currentStatus: MusicAccessStatus {
        MusicAccessStatus(MusicAuthorization.currentStatus)
    }

    @discardableResult
    func requestAccess() async -> MusicAccessStatus {
        MusicAccessStatus(await MusicAuthorization.request())
    }
}

extension MusicAccessStatus {
    init(_ status: MusicAuthorization.Status) {
        switch status {
        case .authorized:    self = .authorized
        case .denied:        self = .denied
        case .restricted:    self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default:    self = .notDetermined
        }
    }
}
