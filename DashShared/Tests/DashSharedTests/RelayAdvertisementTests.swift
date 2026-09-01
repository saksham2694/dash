import Foundation
import Testing
@testable import DashShared

@Suite("RelayAdvertisement TXT-record round-trip")
struct RelayAdvertisementTests {

    @Test("entries round-trip back to an equal value")
    func roundTrip() {
        let original = RelayAdvertisement(id: "8A1F-UUID", displayName: "Saksham's iPhone")

        let rebuilt = RelayAdvertisement(txtRecordEntries: original.txtRecordEntries)

        #expect(rebuilt == original)
    }

    @Test("publishes exactly the agreed keys")
    func keys() {
        let entries = RelayAdvertisement(id: "x", displayName: "y").txtRecordEntries
        #expect(entries.keys.sorted() == ["name", "rid"])
    }

    @Test("a missing or empty id is rejected — no identity, no pairing")
    func rejectsMissingID() {
        #expect(RelayAdvertisement(txtRecordEntries: [:]) == nil)
        #expect(RelayAdvertisement(txtRecordEntries: ["name": "iPhone"]) == nil)
        #expect(RelayAdvertisement(txtRecordEntries: ["rid": "", "name": "iPhone"]) == nil)
    }

    @Test("a missing display name decodes as empty, identity still valid")
    func toleratesMissingName() {
        let ad = RelayAdvertisement(txtRecordEntries: ["rid": "abc"])
        #expect(ad?.id == "abc")
        #expect(ad?.displayName == "")
    }
}
