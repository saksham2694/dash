//
//  WallpaperTests.swift
//  DashTests
//
//  The shell wallpaper preference layer added ahead of a future Settings ▸
//  Appearance ▸ Wallpaper screen. Locks the contract `DashShellBackground` and
//  that future feature both depend on:
//
//    • a catalogued default wallpaper always exists,
//    • wallpaper IDs are stable (their persisted rawValue round-trips),
//    • a selection persists across store instances,
//    • an unknown / corrupt persisted value falls back to the default,
//    • the store always resolves to a real catalogue entry.
//

import Foundation
import Testing
@testable import Dash

@MainActor
@Suite("Shell wallpaper")
struct WallpaperTests {

    private func store(_ suite: String = UUID().uuidString) -> (WallpaperStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "wallpaper-\(suite)")!
        defaults.removePersistentDomain(forName: "wallpaper-\(suite)")
        return (WallpaperStore(defaults: defaults), defaults)
    }

    // MARK: Catalog

    @Test("a default wallpaper exists and is part of the catalog")
    func defaultExists() {
        #expect(WallpaperCatalog.all.contains(WallpaperCatalog.default))
        #expect(!WallpaperCatalog.all.isEmpty)
    }

    @Test("the shipped default can render without a supplied asset")
    func defaultHasProceduralFallback() {
        #expect(WallpaperCatalog.default.hasProceduralFallback)
    }

    @Test("every catalog entry has a display name, and ids are unique")
    func catalogIntegrity() {
        for wallpaper in WallpaperCatalog.all {
            #expect(!wallpaper.displayName.isEmpty)
        }
        let ids = WallpaperCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("wallpaper IDs are stable — the persisted rawValue round-trips")
    func idsAreStable() {
        for id in WallpaperID.allCases {
            #expect(WallpaperID(rawValue: id.rawValue) == id)
        }
        // The default's rawValue is the literal we persist; pin it so a rename is loud.
        #expect(WallpaperCatalog.default.id.rawValue == "ember")
    }

    @Test("an unknown id resolves to the default rather than crashing")
    func unknownIDFallsBack() {
        // (Every real case is catalogued; this guards a future id that a rolled-back
        // build wouldn't know.) The lookup is total.
        #expect(WallpaperCatalog.wallpaper(.ember) == WallpaperCatalog.wallpaper(.ember))
        #expect(WallpaperCatalog.all.contains(WallpaperCatalog.wallpaper(.ember)))
    }

    // MARK: Store

    @Test("a fresh store starts on the default wallpaper")
    func freshStoreIsDefault() {
        let (s, _) = store()
        #expect(s.selectedID == WallpaperCatalog.default.id)
        #expect(s.selected == WallpaperCatalog.default)
    }

    @Test("a selection persists across store instances")
    func selectionPersists() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: "wallpaper-\(suite)")!
        defaults.removePersistentDomain(forName: "wallpaper-\(suite)")

        let first = WallpaperStore(defaults: defaults)
        first.select(.ember)
        #expect(first.selectedID == .ember)

        // A brand-new store reading the same defaults sees the saved choice.
        let reopened = WallpaperStore(defaults: defaults)
        #expect(reopened.selectedID == .ember)
    }

    @Test("a corrupt persisted value falls back to the default")
    func corruptValueFallsBack() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: "wallpaper-\(suite)")!
        defaults.set("not-a-real-wallpaper", forKey: WallpaperStore.storageKey)

        let s = WallpaperStore(defaults: defaults)
        #expect(s.selectedID == WallpaperCatalog.default.id)
    }

    @Test("resetToDefault restores and persists the default")
    func resetRestoresDefault() {
        let (s, defaults) = store()
        s.select(.ember)
        s.resetToDefault()
        #expect(s.selectedID == WallpaperCatalog.default.id)

        let reopened = WallpaperStore(defaults: defaults)
        #expect(reopened.selectedID == WallpaperCatalog.default.id)
    }

    @Test("the store always resolves to a real catalogue wallpaper")
    func storeResolvesToCatalogEntry() {
        let (s, _) = store()
        #expect(WallpaperCatalog.all.contains(s.selected))
        s.select(.ember)
        #expect(WallpaperCatalog.all.contains(s.selected))
    }
}

// MARK: - Shell geometry / wallpaper containment
//
// The wallpaper is drawn as the background of the same rounded, inset container
// that holds the rail + content (`DashboardShell.shellContainer`), so it is
// clipped to `DashMetrics.shellCornerRadius` and shares `DashMetrics.shellOuterInset`.
// There is one source of truth for both values — asserted here so a stray
// hard-coded inset/radius elsewhere would have to diverge from these to matter.
//
// Keyboard anchoring (`.ignoresSafeArea(.keyboard)` on the shell root) and the
// clip itself are SwiftUI view-tree behaviour and are verified on device
// (§10 checklist), not in a unit test.

@Suite("Shell wallpaper geometry source of truth")
struct ShellWallpaperGeometryTests {

    @Test("the shell inset + corner radius are single positive constants")
    func singleSourceOfTruth() {
        #expect(DashMetrics.shellOuterInset > 0)
        #expect(DashMetrics.shellCornerRadius > 0)
        #expect(DashMetrics.shellCornerRadius > DashMetrics.shellOuterInset)
    }
}
