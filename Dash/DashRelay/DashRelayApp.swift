//
//  DashRelayApp.swift
//  DashRelay
//
//  Created by Saksham Sharma on 2026-09-01.
//

import SwiftUI

@main
struct DashRelayApp: App {
    @State private var relay = Relay()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Owns and connects the two halves of the relay for the lifetime of the app.
///
/// `LocationTracker` acquires GPS fixes; `LocationBroadcaster` streams them to iPad
/// clients. The connection is a single line: every packet the tracker produces via
/// its `onPacket` callback is handed straight to `broadcaster.broadcast(_:)`, in the
/// same Core Location callback that produced it (no timer).
@MainActor
private final class Relay {
    let tracker = LocationTracker()
    let broadcaster = LocationBroadcaster()

    init() {
        tracker.onPacket = { [broadcaster] packet in
            broadcaster.broadcast(packet)
        }
        broadcaster.start()
        tracker.start()
    }
}
