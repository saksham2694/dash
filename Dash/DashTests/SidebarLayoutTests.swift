//
//  SidebarLayoutTests.swift
//  DashTests
//
//  M5.5.2a — the fixed navigation rail's deterministic pieces:
//    • rail width + tap-target floors,
//    • which rail app is "selected" for a given shell surface,
//    • the Home/Dashboard toggle's destination for each surface,
//    • `DashAppIcon`'s stable automatic tint (same colour every launch).
//
//  No screenshot tests — just the layout maths and selection logic.
//

import SwiftUI
import Testing
@testable import Dash

@Suite("Navigation rail")
struct SidebarLayoutTests {

    // MARK: Rail metrics

    @Test("the rail is wide enough for a tap target, and its icons meet 44pt")
    func metrics() {
        #expect(DashMetrics.railWidth >= DashMetrics.minTapTarget)
        #expect(DashMetrics.railSlotSize >= DashMetrics.minTapTarget)
        #expect(DashMetrics.railIconSize < DashMetrics.railSlotSize)   // icon fits inside its slot
    }

    // MARK: Selected app

    @Test("the selected rail app is the one currently full-screen, else none")
    func selectedApp() {
        #expect(DashSidebar.selectedApp(for: .app("maps")) == "maps")
        #expect(DashSidebar.selectedApp(for: .app("music")) != "maps")
        #expect(DashSidebar.selectedApp(for: .dashboard) == nil)
        #expect(DashSidebar.selectedApp(for: .home(page: 0)) == nil)
        #expect(DashSidebar.selectedApp(for: .home(page: 3)) == nil)
    }

    // MARK: Home / Dashboard toggle

    @Test("the toggle moves to Home from the Dashboard, and to the Dashboard from anywhere else")
    func toggleDestination() {
        #expect(DashSidebar.toggleDestination(for: .dashboard) == .home)
        #expect(DashSidebar.toggleDestination(for: .home(page: 0)) == .dashboard)
        #expect(DashSidebar.toggleDestination(for: .home(page: 5)) == .dashboard)
        #expect(DashSidebar.toggleDestination(for: .app("maps")) == .dashboard)
        // The glyph differs so the control's meaning is visible, not just its label.
        #expect(DashSidebar.ToggleDestination.home.symbol != DashSidebar.ToggleDestination.dashboard.symbol)
    }

    // MARK: DashAppIcon tint

    @Test("an automatic icon tint is stable and id-derived; a pinned tint wins")
    func iconTint() {
        // Same id → same tint every call (run-independent hash).
        #expect(DashAppIcon.tint(for: .automatic, id: "maps") == DashAppIcon.tint(for: .automatic, id: "maps"))
        // The stable hash itself is deterministic.
        #expect(DashAppIcon.stableHash("maps") == DashAppIcon.stableHash("maps"))
        #expect(DashAppIcon.stableHash("maps") != DashAppIcon.stableHash("music"))
        // Any automatic tint is a real palette member.
        #expect(FeatureTint.allCases.contains(DashAppIcon.tint(for: .automatic, id: "speedometer")))
        // A pinned tint is honoured verbatim.
        #expect(DashAppIcon.tint(for: .pinned(.orange), id: "maps") == .orange)
    }

    @MainActor
    @Test("every registered feature has a symbol + title for its rail icon")
    func manifestsDriveRailIcons() {
        let manifests = FeatureRegistry.makeDefault().manifests
        #expect(!manifests.isEmpty)
        for manifest in manifests {
            #expect(!manifest.symbolName.isEmpty)
            #expect(!manifest.title.isEmpty)
        }
    }
}
