//
//  HomeLayout.swift
//  Dash
//
//  The persisted arrangement of the App-Home launcher: ordered pages, each an
//  ordered list of app placements. SDK-neutral and SwiftUI-free — plain
//  `Codable` value types referencing only `FeatureID`.
//
//  A **separate concept from `DashboardLayout`**: Home is a launcher (which apps,
//  in what order, on which page); Dashboard is a widget grid (sizes + cell
//  positions). They share nothing but `FeatureID`.
//
//  This owns *arrangement*, not runtime feature state. Nothing here knows how an
//  app looks or opens — that is `DashFeature` / the shell. The persistence
//  envelope + schema version live in `HomeLayoutStore`.
//

import Foundation

/// One app tile on a Home page.
nonisolated struct HomeAppPlacement: Identifiable, Equatable, Sendable, Codable {

    /// Stable identity — survives reorder and keys SwiftUI `ForEach`. Assigned
    /// once.
    let id: UUID

    /// Which feature this tile opens (see `FeatureRegistry`).
    var featureID: FeatureID

    init(id: UUID = UUID(), featureID: FeatureID) {
        self.id = id
        self.featureID = featureID
    }
}

/// One page of the App-Home launcher.
nonisolated struct HomePage: Identifiable, Equatable, Sendable, Codable {

    let id: UUID
    var apps: [HomeAppPlacement]

    init(id: UUID = UUID(), apps: [HomeAppPlacement] = []) {
        self.id = id
        self.apps = apps
    }
}

/// The whole App-Home launcher — an ordered list of pages.
nonisolated struct HomeLayout: Equatable, Sendable, Codable {

    var pages: [HomePage]

    init(pages: [HomePage]) {
        self.pages = pages
    }

    var pageCount: Int { pages.count }

    var isEmpty: Bool { pages.allSatisfy { $0.apps.isEmpty } }

    /// The page at `index`, or `nil` when out of range.
    func page(at index: Int) -> HomePage? {
        pages.indices.contains(index) ? pages[index] : nil
    }

    /// `index` clamped to the pages that actually exist (`0` when there are
    /// none). The model-level page-move guard — the view never has to know the
    /// page count.
    func clampedPageIndex(_ index: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return min(max(0, index), pageCount - 1)
    }

    /// Every placement, flattened across pages (page then app order).
    var allApps: [HomeAppPlacement] {
        pages.flatMap(\.apps)
    }
}

extension HomeLayout {

    /// The default launcher, **derived from the registered feature ids** (the
    /// caller passes them so `Shell/` stays feature-agnostic — `DashApp` supplies
    /// `FeatureRegistry`'s ids). One tile per feature, in registration order,
    /// filled `appsPerPage` at a time.
    static func starter(featureIDs: [FeatureID], appsPerPage: Int = 12) -> HomeLayout {
        guard !featureIDs.isEmpty else { return HomeLayout(pages: [HomePage()]) }

        let placements = featureIDs.map { HomeAppPlacement(featureID: $0) }
        let perPage = max(1, appsPerPage)
        let pages = stride(from: 0, to: placements.count, by: perPage).map { start in
            HomePage(apps: Array(placements[start ..< min(start + perPage, placements.count)]))
        }
        return HomeLayout(pages: pages)
    }
}
