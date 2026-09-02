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
//  Not changed in M5.1: the routing / navigation algorithms, the wiring between
//  the view models (that still lives in `MapFullScreenView`, driven by
//  `LocationStore` while the Map screen is on-screen), and the Map UX.
//

import SwiftUI

@MainActor
final class MapFeature: DashFeature {

    /// Stable id — used by the sidebar, Home, and (later) dashboard placements.
    static let id: FeatureID = "maps"

    let manifest = FeatureManifest(
        id: MapFeature.id,
        title: "Maps",
        symbolName: "map.fill",
        supportedSizes: [.compact, .medium, .large, .full],
        defaultSize: .large
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

    /// Dashboard widgets are M5.2 — every widget size shows a placeholder for
    /// now. The real full-screen Map is `makeFullScreenView()`.
    func makeComponentView(size: ComponentSize) -> AnyView {
        AnyView(MapComponentPlaceholder(size: size))
    }
}

/// Temporary stand-in for the Map dashboard widget (M5.2 replaces it with a
/// real reduced-map / maneuver presentation).
private struct MapComponentPlaceholder: View {
    let size: ComponentSize

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "map.fill").font(.title2)
            Text("Maps").font(.headline)
            Text("\(size.rawValue) widget — M5.2")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
