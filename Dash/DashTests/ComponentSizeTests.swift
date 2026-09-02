//
//  ComponentSizeTests.swift
//  DashTests
//
//  The SDK-neutral component-size enum introduced by the M5.0 shell seam.
//

import Foundation
import Testing
@testable import Dash

@Suite("ComponentSize")
struct ComponentSizeTests {

    @Test("widget sizes are compact / medium / large — never full")
    func widgetSizes() {
        #expect(ComponentSize.widgetSizes == [.compact, .medium, .large])
        #expect(!ComponentSize.widgetSizes.contains(.full))
    }

    @Test("isWidget is true for every size except full")
    func isWidget() {
        #expect(ComponentSize.compact.isWidget)
        #expect(ComponentSize.medium.isWidget)
        #expect(ComponentSize.large.isWidget)
        #expect(!ComponentSize.full.isWidget)
    }

    @Test("round-trips through Codable")
    func codable() throws {
        for size in ComponentSize.allCases {
            let data = try JSONEncoder().encode(size)
            #expect(try JSONDecoder().decode(ComponentSize.self, from: data) == size)
        }
    }
}
