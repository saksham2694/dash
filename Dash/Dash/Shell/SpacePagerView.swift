//
//  SpacePagerView.swift
//  Dash
//
//  The ONE shell-level horizontal pager. The Dashboard and the Home pages form a
//  single left-to-right sequence of "spaces":
//
//      Dashboard ←→ Home page 0 ←→ Home page 1 ←→ …
//
//  Initially there is just `Dashboard ←→ Home page 0` (one real app, one Home
//  page). `HomeLayout.paginate` adds Home pages automatically as apps are added;
//  each new page appears after the last one in this same sequence.
//
//  There is exactly one Dashboard — no Dashboard pages. Swiping is *additional*
//  to the sidebar, not a replacement: the sidebar's Home / Dashboard / app
//  buttons still jump directly.
//
//  A native `TabView` drives the paging. Its selection is a flat "space index"
//  (`ShellSurface.spaceIndex` / `.forSpaceIndex`); it is kept in sync with
//  `ShellStore.surface` both ways so a sidebar tap and a swipe stay consistent.
//  `.app` (a full-screen feature) is shown by `DashboardShell` *instead of* this
//  pager, so it never appears here.
//

import SwiftUI

struct SpacePagerView: View {

    @ObservedObject private var shell: ShellStore
    @ObservedObject private var homeLayout: HomeLayoutStore
    @ObservedObject private var dashboardLayout: DashboardLayoutStore
    @ObservedObject private var dashboardEdit: DashboardEditModel

    private let registry: FeatureRegistry
    private let grid: DashboardGrid

    /// The pager's current space index. `0` = Dashboard, `1…` = Home page `0…`.
    /// Seeded from the shell surface, kept synced both ways. Never persisted.
    @State private var spaceIndex: Int

    init(
        shell: ShellStore,
        homeLayout: HomeLayoutStore,
        dashboardLayout: DashboardLayoutStore,
        dashboardEdit: DashboardEditModel,
        registry: FeatureRegistry,
        grid: DashboardGrid
    ) {
        _shell = ObservedObject(wrappedValue: shell)
        _homeLayout = ObservedObject(wrappedValue: homeLayout)
        _dashboardLayout = ObservedObject(wrappedValue: dashboardLayout)
        _dashboardEdit = ObservedObject(wrappedValue: dashboardEdit)
        self.registry = registry
        self.grid = grid

        let pageCount = max(1, homeLayout.layout.pageCount)
        _spaceIndex = State(initialValue: shell.surface.spaceIndex(homePageCount: pageCount) ?? 0)
    }

    // MARK: - Derived

    private var homePages: [HomePage] { homeLayout.layout.pages }
    private var homePageCount: Int { max(1, homePages.count) }
    private var lastSpaceIndex: Int { ShellSurface.spaceCount(homePageCount: homePageCount) - 1 }

    // MARK: - Test-facing

    /// The pager's current space index.
    var currentSpaceIndex: Int { spaceIndex }

    /// The `ShellSurface` the current space index maps to.
    var surfaceForCurrentSpace: ShellSurface {
        ShellSurface.forSpaceIndex(spaceIndex, homePageCount: homePageCount)
    }

    /// The Home page the dots should highlight, or `nil` on the Dashboard.
    var currentHomePage: Int? { surfaceForCurrentSpace.homePage }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $spaceIndex) {
                DashboardSpaceView(
                    layoutStore: dashboardLayout,
                    editModel: dashboardEdit,
                    registry: registry,
                    grid: grid,
                    onOpenFeature: { shell.openApp($0) }
                )
                .tag(0)

                ForEach(Array(homePages.enumerated()), id: \.element.id) { entry in
                    HomeSpaceView(
                        page: entry.element,
                        registry: registry,
                        onOpenFeature: { shell.openApp($0) }
                    )
                    .tag(entry.offset + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if let homePage = currentHomePage, homePageCount > 1 {
                HomePageDots(count: homePageCount, current: homePage) { index in
                    withAnimation(.easeInOut(duration: 0.25)) { spaceIndex = index + 1 }
                }
                .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: spaceIndex) { _, newValue in
            applyToShell(newValue)
        }
        .onChange(of: shell.surface) { _, _ in
            syncFromShell()
        }
        .onChange(of: homePageCount) { _, _ in
            let clamped = min(max(0, spaceIndex), lastSpaceIndex)
            if clamped != spaceIndex { spaceIndex = clamped }
        }
    }

    // MARK: - Two-way sync

    /// A swipe / dot settled on `index` → move the shell there. Guarded so a
    /// change that originated from the shell isn't echoed straight back, and so
    /// a full-screen app (shown instead of the pager) is never disturbed.
    private func applyToShell(_ index: Int) {
        guard !shell.surface.isApp else { return }
        let target = ShellSurface.forSpaceIndex(index, homePageCount: homePageCount)
        guard target != shell.surface else { return }

        switch target {
        case .dashboard:
            shell.showDashboard()
        case .home(let page):
            shell.showHome(page: page)
        case .app:
            break
        }
    }

    /// The shell surface changed (a sidebar tap, `goToPage`, closing an app) →
    /// move the pager to match.
    private func syncFromShell() {
        guard let index = shell.surface.spaceIndex(homePageCount: homePageCount) else { return }
        if index != spaceIndex {
            withAnimation(.easeInOut(duration: 0.25)) { spaceIndex = index }
        }
    }
}
