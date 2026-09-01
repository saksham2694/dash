//
//  RelayStatusViewTests.swift
//  DashRelayTests
//
//  The pure session-state → screen mapping behind the DashRelay status screen.
//  No GPS, no Bonjour.
//

import Testing
@testable import DashRelay

@MainActor
@Suite("RelayStatusView.Display")
struct RelayStatusViewTests {

    @Test("stopped: offers Start, no activity indicator")
    func stopped() {
        let d = RelayStatusView.Display(.stopped)
        #expect(d.action == .start)
        #expect(d.showsActivity == false)
    }

    @Test("waiting: ready, shows activity, offers Stop Sharing")
    func waiting() {
        let d = RelayStatusView.Display(.waiting)
        #expect(d.action == .stopSharing)
        #expect(d.showsActivity)
        #expect(d.title == "Ready to Connect")
    }

    @Test("connected: offers Disconnect, no activity indicator")
    func connected() {
        let d = RelayStatusView.Display(.connected)
        #expect(d.action == .disconnect)
        #expect(d.showsActivity == false)
    }

    @Test("the waiting state can be stopped rather than left running forever")
    func waitingIsStoppable() {
        // stopped → only Start; waiting → Stop Sharing; connected → Disconnect.
        #expect(RelayStatusView.Display(.stopped).action == .start)
        #expect(RelayStatusView.Display(.waiting).action == .stopSharing)
        #expect(RelayStatusView.Display(.connected).action == .disconnect)
    }

    @Test("every state has a non-empty title and message")
    func textPresent() {
        for state in [RelaySessionController.State.stopped, .waiting, .connected] {
            let d = RelayStatusView.Display(state)
            #expect(d.title.isEmpty == false)
            #expect(d.message.isEmpty == false)
            #expect(d.symbolName.isEmpty == false)
        }
    }

    @Test("Disconnect is offered only when connected")
    func disconnectOnlyWhenConnected() {
        #expect(RelayStatusView.Display(.stopped).action != .disconnect)
        #expect(RelayStatusView.Display(.waiting).action != .disconnect)
        #expect(RelayStatusView.Display(.connected).action == .disconnect)
    }
}
