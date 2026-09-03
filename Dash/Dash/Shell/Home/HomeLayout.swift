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

/// The launcher's design grid — the capacity that drives Home pagination and
/// the icon layout. A design constant; not persisted. Icons fill this grid
/// top-left, left-to-right then top-to-bottom; when it is full, a new Home
/// page is added.
nonisolated enum HomeGrid {
    static let columns = 4
    static let rows = 4

    /// App icons per Home page.
    static var capacity: Int { columns * rows }
}

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

    /// Paginate a list of feature ids into Home pages, **`capacity` icons per
    /// page**, filling each page top-left before starting the next. Pure and
    /// testable. The caller passes the ids so `Shell/` stays feature-agnostic
    /// (`DashApp` supplies `FeatureRegistry`'s ids and `HomeGrid.capacity`).
    ///
    /// No empty pages: an empty id list yields a single empty page; otherwise
    /// the page count is exactly `ceil(count / capacity)`.
    ///
    ///     paginate(5 ids,  capacity: 8) → 1 page
    ///     paginate(10 ids, capacity: 8) → 2 pages
    ///     paginate(17 ids, capacity: 8) → 3 pages
    static func paginate(featureIDs: [FeatureID], capacity: Int = HomeGrid.capacity) -> HomeLayout {
        guard !featureIDs.isEmpty else { return HomeLayout(pages: [HomePage()]) }

        let placements = featureIDs.map { HomeAppPlacement(featureID: $0) }
        let perPage = max(1, capacity)
        let pages = stride(from: 0, to: placements.count, by: perPage).map { start in
            HomePage(apps: Array(placements[start ..< min(start + perPage, placements.count)]))
        }
        return HomeLayout(pages: pages)
    }
}
