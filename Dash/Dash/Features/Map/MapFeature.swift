//
//  MapFeature.swift
//  Dash
//
//  The Map feature's adapter to the shell, and — as of M5.1 — the **app-scoped
//  owner of the Map runtime state**.
//
//  Before M5.1 the five Map view models were `@StateObject`s inside
//  `ContentView`, so they were torn down and rebuilt every time the Map screen
//  left the view tree (e.g. Maps → Home → Maps), losing any active route /
//  navigation session. Now they live here, for the life of the app:
//  `makeFullScreenView()` hands `MapFullScreenView` references to these
//  instances, it does not create new ones.
//
//  This is still the *only* bridge between `Shell/` and Map internals. The shell
//  never sees `MapViewModel` / `RouteViewModel` / `NavigationViewModel` / … —
//  only `DashFeature`.
//
//  M5.2.1 adds the real dashboard widgets (`makeComponentView`) and a small
//  deduped fix pump (`dashboardObserve`) so a live navigation session stays
//  current while a Map dashboard component — rather than `MapFullScreenView` —
//  is what's on screen. The routing / navigation algorithms and the full-screen
//  Map UX are unchanged; the off-route → auto-reroute *adoption* still happens
//  only in `MapFullScreenView`.
//

import DashShared
import SwiftUI

@MainActor
final class MapFeature: DashFeature {

    /// Stable id — used by the sidebar, Home, and (later) dashboard placements.
    static let id: FeatureID = "maps"

    let manifest = FeatureManifest(
        id: MapFeature.id,
        title: "Google Maps",
        symbolName: "map.fill",
        supportedSizes: [.compact, .medium, .large, .full],
        defaultSize: .large,
        iconStyle: .pinned(.green),
        iconAssetName: "app-icon-google-maps"
    )

    // MARK: - App-scoped Map runtime state
    //
    // Owned here so it survives the Map screen leaving and re-entering the view
    // tree. `MapFullScreenView` observes these; it never creates its own.

    /// Drives the active map provider: camera, overlays, mode, follow state,
    /// the selected route / route options, live navigation progress.
    let mapViewModel: MapViewModel

    /// Source of truth for the chosen destination.
    let destinationStore: DestinationStore

    /// Catalog autocomplete + resolve-to-`Destination`.
    let searchViewModel: PlaceSearchViewModel

    /// Route computation + manual / automatic refresh state.
    let routeViewModel: RouteViewModel

    /// Turn-by-turn session: maneuver card, progress, ETA, off-route signal.
    let navigationViewModel: NavigationViewModel

    /// Injectable for tests; production uses the real, SDK-backed services.
    init(
        mapViewModel: MapViewModel? = nil,
        destinationStore: DestinationStore? = nil,
        searchViewModel: PlaceSearchViewModel? = nil,
        routeViewModel: RouteViewModel? = nil,
        navigationViewModel: NavigationViewModel? = nil
    ) {
        self.mapViewModel = mapViewModel ?? MapViewModel()
        self.destinationStore = destinationStore ?? DestinationStore()
        self.searchViewModel = searchViewModel ?? PlaceSearchViewModel(service: GooglePlaceSearchService())
        self.routeViewModel = routeViewModel ?? RouteViewModel(service: GoogleRouteService())
        self.navigationViewModel = navigationViewModel ?? NavigationViewModel()

        // One-time wiring that `ContentView` used to do in `.task`. Both objects
        // are feature-owned, so it belongs here and persists for the app's life.
        // `[weak self]` breaks the feature → searchViewModel → closure → feature
        // cycle.
        self.searchViewModel.onDestinationChosen = { [weak self] destination in
            self?.destinationStore.select(destination)
        }
    }

    /// Built once. The shell can re-evaluate its `body` for unrelated reasons
    /// (connection state churn, sidebar toggles); handing back the same view
    /// value keeps the map from being rebuilt underneath an active session while
    /// Maps stays on screen. Leaving Maps entirely still tears the map view down
    /// and rebuilds it on return — but from the app-scoped state above, so the
    /// route / navigation session is intact.
    private lazy var fullScreenView = AnyView(MapFullScreenView(feature: self))

    /// The full-screen Map experience, backed by the app-scoped state above.
    func makeFullScreenView() -> AnyView {
        fullScreenView
    }

    /// One cached dashboard view per size — same reasoning as `fullScreenView`:
    /// `DashboardSpaceView` can re-evaluate its `body` for unrelated reasons
    /// (connection-state churn), and handing back the same view value keeps the
    /// widget map from being rebuilt. `MapComponentView` is stateless (`feature`
    /// + `size`), so a layout that placed two widgets of one size would simply
    /// render the same value in each grid slot.
    private var componentViews: [ComponentSize: AnyView] = [:]

    /// A real Map dashboard widget (M5.2.1). `.large` / `.medium` show a
    /// widget-framed live map; `.compact` shows a glanceable maneuver / destination
    /// readout with no map. Every size observes the app-scoped view models above —
    /// no new `MapViewModel` / `NavigationViewModel` / … is created.
    func makeComponentView(size: ComponentSize) -> AnyView {
        if let cached = componentViews[size] { return cached }
        let view = AnyView(MapComponentView(feature: self, size: size))
        componentViews[size] = view
        return view
    }

    // MARK: - Dashboard fix pump (M5.2.1)

    /// Timestamp of the last fix pumped in via `dashboardObserve`. Several
    /// mounted map widgets each call `dashboardObserve` per fix; this dedupes
    /// them so the shared engine — in particular the M4.6 off-route detector,
    /// which *counts* fixes — advances exactly once per fix.
    private(set) var lastObservedDashboardFix: Date?

    /// Feed the latest `LocationStore` fix into the shared view models while a
    /// Map dashboard component is mounted, so a live navigation session
    /// (vehicle, follow camera, route clip, maneuver progress, ETA) stays
    /// current on the dashboard — not just in `MapFullScreenView`.
    ///
    /// This does **not** run the off-route → auto-reroute *adoption* path (that
    /// stays in `MapFullScreenView`); the detector still classifies each fix, and
    /// a reroute request it raises here is serviced when the full-screen view is
    /// next shown.
    func dashboardObserve(_ packet: LocationPacket?) {
        guard let packet, packet.timestamp != lastObservedDashboardFix else { return }
        lastObservedDashboardFix = packet.timestamp

        mapViewModel.update(with: packet)
        navigationViewModel.update(
            with: MapCoordinate(latitude: packet.latitude, longitude: packet.longitude)
        )
        mapViewModel.setNavigationProgress(navigationViewModel.progress)
    }
}
