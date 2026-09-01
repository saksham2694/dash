//
//  DashRelayApp.swift
//  DashRelay
//
//  Created by Saksham Sharma on 2026-09-01.
//

import SwiftUI

@main
struct DashRelayApp: App {

    /// The connection/session layer — owns GPS + networking and their lifecycle.
    @StateObject private var session = RelaySessionController()

    var body: some Scene {
        WindowGroup {
            RelayStatusScreen()
                .environmentObject(session)
                .task { session.start() }
        }
    }
}
