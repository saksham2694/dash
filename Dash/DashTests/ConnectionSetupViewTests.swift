//
//  ConnectionSetupViewTests.swift
//  DashTests
//
//  The pure Model → Display mapping behind the connection/setup screen: when a
//  device list is shown, when the "looking for your paired iPhone" message is
//  shown, when the search can be stopped, and how the Forget button is labelled.
//

import Testing
@testable import Dash

@MainActor
@Suite("ConnectionSetupView.Display")
struct ConnectionSetupViewTests {

    private func relay(_ id: String, _ name: String) -> DiscoveredRelay {
        DiscoveredRelay(id: id, displayName: name)
    }

    @Test("disconnected: idle, offers to search, no spinner or list")
    func disconnected() {
        let d = ConnectionSetupView.Display(.init(state: .disconnected))
        #expect(d.showsSpinner == false)
        #expect(d.relayChoices.isEmpty)
        #expect(d.action == .search)
    }

    @Test("discovering, nothing found: spinner, no list, offers Stop Searching")
    func discoveringEmpty() {
        let d = ConnectionSetupView.Display(.init(state: .discovering))
        #expect(d.showsSpinner)
        #expect(d.relayChoices.isEmpty)
        #expect(d.action == .stopSearching)
    }

    @Test("discovering with candidates and no pairing: shows the device list")
    func discoveringShowsList() {
        let relays = [relay("a", "iPhone A"), relay("b", "iPhone B")]
        let d = ConnectionSetupView.Display(.init(state: .discovering, offerableRelays: relays))
        #expect(d.relayChoices == relays)
        #expect(d.showsSpinner == false)
        #expect(d.action == .stopSearching)
        #expect(d.showsForget == false)
    }

    @Test("discovering while paired but relay not visible: 'looking for <name>', no list")
    func discoveringLookingForPaired() {
        let d = ConnectionSetupView.Display(
            .init(state: .discovering, offerableRelays: [], pairedRelayName: "Sak's iPhone")
        )
        #expect(d.showsSpinner)
        #expect(d.relayChoices.isEmpty)
        #expect(d.statusText.contains("Sak's iPhone"))
        #expect(d.showsForget)
    }

    @Test("connecting: spinner, offers Stop Searching, names the paired relay")
    func connecting() {
        let d = ConnectionSetupView.Display(.init(state: .connecting, pairedRelayName: "Sak's iPhone"))
        #expect(d.showsSpinner)
        #expect(d.relayChoices.isEmpty)
        #expect(d.action == .stopSearching)
        #expect(d.statusText.contains("Sak's iPhone"))
    }

    @Test("connected: no action, no list")
    func connected() {
        let d = ConnectionSetupView.Display(.init(state: .connected))
        #expect(d.showsSpinner == false)
        #expect(d.relayChoices.isEmpty)
        #expect(d.action == .none)
    }

    @Test("Forget button is labelled with the paired device name")
    func forgetLabel() {
        for state in [ConnectionState.disconnected, .discovering, .connecting] {
            let named = ConnectionSetupView.Display(.init(state: state, pairedRelayName: "Sak's iPhone"))
            #expect(named.forgetLabel == "Forget Sak's iPhone")
            #expect(named.showsForget)

            let unpaired = ConnectionSetupView.Display(.init(state: state))
            #expect(unpaired.forgetLabel == nil)
            #expect(unpaired.showsForget == false)
        }
        // A paired-but-nameless relay still gets a sensible label.
        let blank = ConnectionSetupView.Display(.init(state: .discovering, pairedRelayName: ""))
        #expect(blank.forgetLabel == "Forget This iPhone")
        #expect(blank.showsForget)
    }

    @Test("every state has non-empty status text")
    func statusTextPresent() {
        for state in [ConnectionState.disconnected, .discovering, .connecting, .connected] {
            #expect(ConnectionSetupView.Display(.init(state: state)).statusText.isEmpty == false)
        }
    }
}
