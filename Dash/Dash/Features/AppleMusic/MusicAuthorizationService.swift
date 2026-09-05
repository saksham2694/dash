//
//  MusicAuthorizationService.swift
//  Dash — Apple Music feature
//
//  The seam around `MusicAuthorization` (M9.0 §"Authorization"). Every other
//  file in the feature that needs to know "can we talk to MusicKit yet"
//  reads this protocol, never `MusicAuthorization` directly, so a test can
//  substitute a fake status without touching real authorization state.
//

import Foundation

nonisolated enum MusicAccessStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

protocol MusicAuthorizationService: Sendable {
    var currentStatus: MusicAccessStatus { get }
    /// Requests access if needed. Shows the system prompt on first call
    /// (backed by `NSAppleMusicUsageDescription`). Returns the resulting
    /// status.
    @discardableResult
    func requestAccess() async -> MusicAccessStatus
}
