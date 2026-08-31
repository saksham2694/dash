//
//  ConnectionSetupViewTests.swift
//  DashTests
//
//  The pure state → display mapping behind the connection/setup screen. Covers
//  requirement: a Disconnect action only when appropriate.
//

import Testing
@testable import Dash

@MainActor
@Suite("ConnectionSetupView.Display")
struct ConnectionSetupViewTests {

    @Test("disconnected: idle, offers to search, no spinner")
    func disconnected() {
        let d = ConnectionSetupView.Display(.disconnected)
        #expect(d.showsSpinner == false)
        #expect(d.action == .search)
    }

    @Test("discovering: busy, offers Disconnect")
    func discovering() {
        let d = ConnectionSetupView.Display(.discovering)
        #expect(d.showsSpinner)
        #expect(d.action == .disconnect)
    }

    @Test("connecting: busy, offers Disconnect")
    func connecting() {
        let d = ConnectionSetupView.Display(.connecting)
        #expect(d.showsSpinner)
        #expect(d.action == .disconnect)
    }

    @Test("connected: no action (dashboard is shown instead)")
    func connected() {
        let d = ConnectionSetupView.Display(.connected)
        #expect(d.showsSpinner == false)
        #expect(d.action == .none)
    }

    @Test("every state has non-empty status text")
    func statusTextPresent() {
        for state in [ConnectionState.disconnected, .discovering, .connecting, .connected] {
            #expect(ConnectionSetupView.Display(state).statusText.isEmpty == false)
        }
    }
}
