//
//  ConnectedControlViewTests.swift
//  DashTests
//
//  The pure bit of the connected-state control: how it labels the paired iPhone
//  (friendly name, or a fallback when none was given).
//

import Testing
@testable import Dash

@MainActor
@Suite("ConnectedControlView.deviceLabel")
struct ConnectedControlViewTests {

    @Test("uses the friendly name when there is one")
    func usesFriendlyName() {
        #expect(ConnectedControlView.deviceLabel("Saksham’s iPhone") == "Saksham’s iPhone")
    }

    @Test("falls back to 'DashRelay' when the name is missing or blank")
    func fallsBack() {
        #expect(ConnectedControlView.deviceLabel(nil) == "DashRelay")
        #expect(ConnectedControlView.deviceLabel("") == "DashRelay")
    }
}
