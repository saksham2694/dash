//
//  DashBatteryStatusTests.swift
//  DashTests
//
//  `DashBatteryFormatter` (M5.7) — the pure sidebar battery-row presentation:
//  symbol, text, dimming and accessibility for every case the relay produces.
//

import Testing
import DashShared
@testable import Dash

@Suite("DashBatteryFormatter")
struct DashBatteryStatusTests {

    private func f(_ percent: Int?, _ state: BatteryState, _ freshness: DeviceStatusStore.Freshness) -> DashBatteryStatus {
        DashBatteryFormatter.status(percent: percent, state: state, freshness: freshness)
    }

    @Test("a normal discharging percentage shows the level glyph + N%")
    func normal() {
        let s = f(55, .unplugged, .live)
        #expect(s.text == "55%")
        #expect(s.symbolName == "battery.50")
        #expect(s.isDimmed == false)
        #expect(s.accessibilityLabel == "iPhone battery 55 percent")
    }

    @Test("charging uses the bolt glyph and says charging")
    func charging() {
        let s = f(41, .charging, .live)
        #expect(s.symbolName == "battery.100.bolt")
        #expect(s.text == "41%")
        #expect(s.accessibilityLabel.contains("charging"))
    }

    @Test("full plugged in shows 'Full'")
    func full() {
        let s = f(100, .full, .live)
        #expect(s.text == "Full")
        #expect(s.symbolName == "battery.100.bolt")
        #expect(s.accessibilityLabel == "iPhone battery full, charging")
    }

    @Test("100% while merely unplugged still reads Full")
    func hundredUnplugged() {
        #expect(f(100, .unplugged, .live).text == "Full")
    }

    @Test("unavailable is an intentional dimmed glyph with no text — never a dash")
    func unavailable() {
        let s = f(nil, .unknown, .unavailable)
        #expect(s.text == nil)
        #expect(s.isDimmed)
        #expect(s.symbolName == "battery.0")
        #expect(s.accessibilityLabel == "iPhone battery unavailable")
    }

    @Test("a missing level while otherwise available is still treated as unavailable")
    func missingLevel() {
        #expect(f(nil, .unplugged, .live).text == nil)
        #expect(f(nil, .unplugged, .live).isDimmed)
    }

    @Test("stale keeps the last percentage but dims the row and flags 'last known'")
    func stale() {
        let s = f(78, .unplugged, .stale)
        #expect(s.text == "78%")
        #expect(s.isDimmed)
        #expect(s.accessibilityLabel.contains("last known"))
    }

    @Test("the glyph tracks the charge bucket")
    func glyphBuckets() {
        #expect(f(5, .unplugged, .live).symbolName == "battery.0")
        #expect(f(25, .unplugged, .live).symbolName == "battery.25")
        #expect(f(50, .unplugged, .live).symbolName == "battery.50")
        #expect(f(80, .unplugged, .live).symbolName == "battery.75")
        #expect(f(95, .unplugged, .live).symbolName == "battery.100")
    }

    @Test("an out-of-range percentage is clamped")
    func clamps() {
        #expect(f(-5, .unplugged, .live).text == "0%")
        #expect(f(150, .unplugged, .live).text == "Full")
    }
}
