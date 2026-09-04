# PROJECT_STATUS.md

Living status document for **Dash**. It describes the repository as it actually
stands so a future developer (or a fresh Claude Code session) can get oriented
without conversation history.

- **Last updated:** 2026-09-03
- **Branch:** `main`
- **Latest commit:** `e8e913f refactor(map): make map state app-scoped` — dashboard
  **M5.1** (the Map feature's runtime state is now app-scoped so it survives
  leaving/returning to Maps, §5 item 33).
- **Everything through M5.1 is committed.** Connection/pairing/relay-status →
  `9a02364` / `ec4d4a9` / `c3a3a18`; Map **M1** + **M2** → `973ffc9`; **M3** →
  `28b5be5` (Routes API device-verified; carries the `X-Ios-Bundle-Identifier`
  header); **M4.1** → `8255749`; **M4.2** → `d8b291e`; **M4.3** → `a262a9c`;
  **M4.4** → `4697557`; **M4.5** → `678e478`; **M4.6** → `73879e7`;
  dashboard shell **M5.0** → `258ffde`; dashboard **M5.1** → `e8e913f`. See §10
  for the mapping.
- **Working tree (not yet committed):** **Dashboard "M5.2.0" — the widget-grid
  layout foundation** (§5 item 34). New `Shell/Dashboard/`: an SDK-neutral
  `Codable` **`DashboardLayout`** (ordered pages → ordered `WidgetPlacement`s,
  each `{ id: UUID, featureID, size: ComponentSize, origin: GridPoint }`),
  **`DashboardGrid`** (the fixed **6 × 4** cell grid + the `ComponentSize` →
  cell-footprint mapping — `.compact` 2×1 / `.medium` 3×2 / `.large` 6×2), a pure
  **`DashboardLayoutValidator`** (structural: duplicate ids / non-widget size /
  out-of-bounds / per-page overlap; registry-aware: unknown feature / unsupported
  size), and **`DashboardLayoutStore`** — `@MainActor ObservableObject` persisting
  a schema-versioned JSON envelope under **`shell.dashboardLayout.v1`** in
  `UserDefaults`, falling back to the injected seed on missing / undecodable /
  wrong-version / structurally-invalid data. **`DashboardSpaceView`** replaces
  `DashboardPlaceholderView`: it reads the store, resolves each placement's
  `featureID` through `FeatureRegistry`, calls `DashFeature.makeComponentView(size:)`
  (still a labelled placeholder for Maps until M5.2.1), absolute-positions widgets
  on the grid, and offers simple prev/next + page dots. `DashApp` seeds
  `DashboardLayoutStore` with **`DashboardLayout.starter(featureID: MapFeature.id)`**
  — a **two-page Maps-only** layout (page 1: large + medium + compact; page 2:
  large + medium) proving multi-size / multi-position / multi-page. `DashboardShell`
  owns the grid constant and the `.dashboard(page:)` → `DashboardSpaceView` wiring;
  it still has **zero** references to `MapViewModel` / `RouteViewModel` /
  `NavigationViewModel`. **No** Map component rendering, no editing / drag / resize,
  no Speedometer / Music / `ThemeManager`. Full suite **347/347**, build clean,
  **device-verified on the physical iPad**. See §5 item 34, §10.
- **Authoritative requirements:** `PROJECT_SPEC.pdf` (repo root) — "iPad CarPlay-style Dashboard — Project Spec"
- **Day-to-day guidance:** `CLAUDE.md` (repo root)

### How to read the status tags

| Tag | Meaning |
|---|---|
| **[Implemented]** | Code exists in the repo and compiles. |
| **[Verified · automated]** | Covered by a passing test in this repo (Swift Testing). |
| **[Verified · on device]** | Confirmed working on real hardware by the developer (not reproducible from this repo alone). |
| **[Planned]** | Agreed next work, not yet started. |
| **[Future idea]** | In the spec's "nice to have" list or noted for later; not scheduled. |

---

## 1. Project overview

Dash is a personal-use, sideloaded infotainment system for a 2019 Honda Amaze
that has no factory touchscreen or CarPlay. A dashboard-mounted, WiFi-only iPad
(no cellular, no GPS chip) runs a custom SwiftUI app styled to resemble Apple
CarPlay. Because the iPad has no GPS, location is relayed from the driver's
iPhone over the Personal Hotspot LAN by a companion app.

It is **not** the real CarPlay framework (that needs OEM head-unit hardware) —
it is a normal iPad app. Single developer, single user, sideloaded with a paid
Apple Developer account; **no App Store distribution**.

Two apps, one shared package:

| Component | Runs on | Role |
|---|---|---|
| **Dash** | iPad | The dashboard UI. Receives location, will host map / music / speedometer. |
| **DashRelay** | iPhone | Background companion. Reads GPS and streams it to the iPad. |
| **DashShared** | (local Swift package) | The wire contract — `LocationPacket` and JSON/framing — imported by both apps so sender and receiver can't drift. |

See `PROJECT_SPEC.pdf` for the full product brief and `CLAUDE.md` for the
condensed architecture rules.

---

## 2. Current architecture

### Repository layout (actual)

```
dash/
├── PROJECT_SPEC.pdf                 # source of truth
├── CLAUDE.md                        # working guidance
├── PROJECT_STATUS.md               # this file
├── .gitignore                       # ignores Dash/Config/GoogleMapsService.xcconfig
├── DashShared/                      # local Swift package (swift-tools 6.3, Swift 6 mode)
│   ├── Package.swift
│   ├── Sources/DashShared/
│   │   ├── LocationPacket.swift       # Codable wire model: latitude, longitude, speed, heading, timestamp
│   │   ├── LocationWireFormat.swift   # bonjourServiceType "_dashrelay._tcp", ISO-8601 JSON coder, \n framing
│   │   └── RelayAdvertisement.swift   # TXT-record contract: stable relay `id` + `displayName` (pairing identity)
│   └── Tests/DashSharedTests/
│       ├── LocationPacketTests.swift
│       └── RelayAdvertisementTests.swift
└── Dash/
    ├── Dash.xcodeproj               # one project, 6 targets: Dash, DashTests, DashUITests,
    │                                #   DashRelay, DashRelayTests, DashRelayUITests
    ├── Config/
    │   ├── GoogleMapsService.xcconfig          # git-ignored, holds the real API key
    │   └── GoogleMapsService.xcconfig.template # committed template
    ├── Dash/                        # iPad app target
    │   ├── DashApp.swift            # @main; owns LocationStore + ConnectionCoordinator + KnownDeviceStore + FeatureRegistry + DashboardLayoutStore; bootstraps Google Maps + Places
    │   ├── RootView.swift           # connection gate: DashboardShell when isConnected, else ConnectionSetupView
    │   ├── Info.plist               # NSBonjourServices, GoogleMapsAPIKey = $(GOOGLE_MAPS_API_KEY)
    │   ├── Configuration/
    │   │   ├── GoogleMapsConfiguration.swift   # reads key from Info.plist, calls GMSServices.provideAPIKey; also exposes `apiKey`
    │   │   └── GooglePlacesConfiguration.swift # calls GMSPlacesClient.provideAPIKey with the SAME key
    │   ├── Core/
    │   │   ├── LocationReceiver.swift          # NWBrowser + NWConnection; reads relay identity from the TXT record; targets ONE relay, reconnects only to it
    │   │   ├── LocationReceiving.swift         # protocol seam: start()/stop()/setTargetRelay(id:) + onDiscoveryChange (DI for ConnectionCoordinator tests)
    │   │   ├── DiscoveredRelay.swift           # transient discovery result: stable id + displayName (distinct from KnownRelay)
    │   │   ├── PacketLineBuffer.swift          # reassembles \n-delimited JSON → [LocationPacket]
    │   │   ├── LocationStore.swift             # single source of truth for location DATA + watchdog (no longer owns the transport)
    │   │   ├── ConnectionState.swift           # enum: disconnected / discovering / connecting / connected
    │   │   ├── ConnectionCoordinator.swift     # session layer: owns the transport, bridges pairing→connection (prefer paired, ignore strangers), feeds LocationStore
    │   │   └── KnownDeviceStore.swift          # pairing / known-device persistence (KnownRelay, keyed by stable relay id); pairedRelay convenience
    │   ├── Shell/                             # M5 — the CarPlay-style shell (SwiftUI + Foundation only; NO Map internals)
    │   │   ├── DashboardShell.swift            # M5.0 — the single layout/navigation owner: persistent SidebarView + content switching on ShellSurface (Home / Dashboard / full-screen app); owns the DashboardGrid constant
    │   │   ├── ShellSurface.swift              # M5.0 — enum: home(page) / dashboard(page) / app(FeatureID); Codable, defaultSurface
    │   │   ├── ShellStore.swift                # M5.0 — @MainActor ObservableObject: surface, sidebarCollapsed, returnSurface; showHome/showDashboard/goToPage/openApp/closeApp/toggleSidebar (pure, feature-agnostic)
    │   │   ├── SidebarView.swift               # M5.0 — persistent nav rail (Home / Dashboard / one button per registered feature) + ConnectedControlView pinned at the bottom (presentational; takes FeatureManifests only)
    │   │   ├── HomePlaceholderView.swift       # M5.0 — simple app-tile launcher: a tile per registered feature + "coming soon" tiles (real multi-page/reorder launcher is later)
    │   │   └── Dashboard/                      # M5.2.0 — the widget dashboard (SDK-neutral except the SwiftUI view)
    │   │       ├── DashboardGrid.swift         # GridPoint / GridSpan / GridRect (half-open rect + intersects); DashboardGrid (.standard = 6×4) + span(for: ComponentSize) footprint mapping + rect(for:) + contains(_:)
    │   │       ├── DashboardLayout.swift       # Codable value types: WidgetPlacement (id: UUID, featureID, size, origin) / DashboardPage / DashboardLayout (pages, page(at:), allPlacements); DashboardLayout.starter(featureID:) — the two-page Maps seed
    │   │       ├── DashboardLayoutValidator.swift  # pure: validate(_:grid:) structural (dup id / non-widget size / out-of-bounds / per-page overlap) + @MainActor validate(_:grid:registry:) (unknown feature / unsupported size); DashboardLayoutIssue
    │   │       ├── DashboardLayoutStore.swift  # @MainActor ObservableObject; loads/persists a { version, layout } JSON envelope under "shell.dashboardLayout.v1" in UserDefaults; falls back to the injected seed on missing/undecodable/wrong-version/structurally-invalid; replace(with:) / resetToDefault()
    │   │       └── DashboardSpaceView.swift    # replaces DashboardPlaceholderView: reads DashboardLayoutStore, resolves featureID via FeatureRegistry → DashFeature.makeComponentView(size:), absolute-positions widgets on the grid, prev/next + page dots; WidgetHostView + UnresolvedWidgetView fallback
    │   ├── Features/
    │   │   ├── DashFeature.swift               # M5.0 — FeatureID (= String) + FeatureManifest (id, title, symbolName, supportedSizes, defaultSize) + @MainActor protocol DashFeature { manifest; makeFullScreenView() -> AnyView; makeComponentView(size:) -> AnyView }
    │   │   ├── ComponentSize.swift             # M5.0 — enum compact/medium/large/full; widgetSizes; isWidget
    │   │   └── FeatureRegistry.swift           # M5.0 — @MainActor ObservableObject: ordered [any DashFeature] + feature(_:) lookup + duplicateIDs(in:) (precondition on init); FeatureRegistry.makeDefault() = the one place the feature set is declared ([MapFeature()])
    │   ├── Features/Connection/
    │   │   ├── ConnectionSetupView.swift       # not-connected / setup screen: device picker + "name this iPhone" prompt, "looking for <paired>", "Stop Searching", Forget <name> (presentational)
    │   │   └── ConnectedControlView.swift      # compact control shown in the shell sidebar while connected: names the iPhone, offers Disconnect / Forget (presentational)
    │   └── Features/Map/                       # all SDK-neutral except GoogleMapProvider.swift
    │       ├── MapFeature.swift                # M5.0/M5.1 — the ONLY bridge between Shell/ and Map internals: app-scoped owner of MapViewModel + DestinationStore + PlaceSearchViewModel + RouteViewModel + NavigationViewModel; makeFullScreenView() → a cached AnyView(MapFullScreenView); makeComponentView() → placeholder (M5.2.1 replaces it)
    │       ├── MapFullScreenView.swift         # was ContentView until M5.1 — the full-screen Map: DashMapView + MapSearchView overlay; OBSERVES MapFeature's view models (no @StateObject); wires them together + the M4.6 off-route signal → auto-reroute + recommended-route adoption
    │       ├── MapProvider.swift               # rendering-only protocol (MapContent in, MapEvent out) + MapProviderID
    │       ├── MapGeometry.swift               # MapCoordinate + MapCoordinateBounds (tightest-box math)
    │       ├── MapCameraState.swift            # camera value type + following(_:); MapCameraPlan (.follow / .fit / .navigation(pitch, vehicleVerticalAnchor))
    │       ├── MapContent.swift                # the render state: camera plan, vehicle indicator, polylines, markers
    │       ├── VehicleIndicator.swift          # M4.1 — SDK-neutral current-location: coordinate + optional heading (from LocationPacket)
    │       ├── MapOverlay.swift                # MapPolyline (+ role: selected/alternative, M4.5) + MapMarker (identified, diffable overlay descriptors)
    │       ├── MapEvent.swift                  # taps (map / POI / marker / route, M4.5) + camera-idle (byUserGesture, M4.2-filtered); MapPOI, MapCameraPosition
    │       ├── MapMode.swift                   # cruising / destinationPreview / navigating (all realised; startNavigation() enters navigating, M4.3)
    │       ├── MapViewModel.swift              # owns mode + route + routeOptions (M4.5 selection) + followsVehicle + navigationProgress; setRouteOptions / selectRouteOption (also the M4.6 auto-reroute adopt path); startNavigation(); dynamic nav zoom; clips + roles the route polylines; derives MapContent
    │       ├── DashMapView.swift               # neutral SwiftUI component; overlays the RecenterButton (M4.2)
    │       ├── RecenterButton.swift            # M4.2 — small "resume follow" affordance (presentational; NOT in GoogleMapProvider)
    │       ├── GoogleMapProvider.swift         # ONLY Map file importing GoogleMaps; wraps GMSMapView, diffs overlays + vehicle + camera, UserGestureLatch (willMove-based)
    │       ├── Search/                         # M2 — destination search (all SDK-neutral except GooglePlaceSearchService.swift)
    │       │   ├── Destination.swift           # Destination + PlaceSuggestion value types
    │       │   ├── PlaceSearchService.swift    # provider-neutral protocol (suggestions / details) + PlaceSearchError
    │       │   ├── GooglePlaceSearchService.swift  # ONLY Map file importing GooglePlaces; autocomplete + place details (New), session token
    │       │   ├── DestinationStore.swift      # @MainActor ObservableObject — the chosen Destination? (source of truth)
    │       │   ├── PlaceSearchViewModel.swift  # SDK-free: debounce, suggestions, resolve-to-Destination via onDestinationChosen
    │       │   └── MapSearchView.swift         # custom search field + suggestions list + selected-destination chip (presentational)
    │       ├── Routing/                        # M3–M4.6 — driving route, turn-by-turn, ETA, alternatives, off-route detection (NO SDK anywhere; GoogleRouteService is REST-only)
    │       │   ├── Route.swift                 # SDK-neutral: id (M4.5) + polyline + distanceMeters + Duration + steps [RouteStep] (M4.3)
    │       │   ├── OffRouteDetector.swift      # M4.6 — pure classifier: onRoute/possiblyOffRoute/confirmedOffRoute + once-per-episode reroute signal (reuses RouteGeometry.project)
    │       │   ├── RouteStep.swift             # M4.3 — SDK-neutral maneuver: ManeuverType + instruction + roadName + maneuverPoint + polyline + distance
    │       │   ├── RouteOptions.swift          # M4.5 — SDK-neutral: routes [Route] + selectedID + summaries (duration/distance/relative label)
    │       │   ├── RouteService.swift          # provider-neutral protocol (routes(from:to:) → [Route], M4.5) + RouteError
    │       │   ├── GoogleRouteService.swift    # Google Routes API over URLSession; Foundation only; computeAlternativeRoutes + legs[].steps[] + Google maneuver vocab
    │       │   ├── GooglePolyline.swift        # pure encoded-polyline decoder
    │       │   ├── RouteGeometry.swift         # M4.3 — pure geodesic: haversine, polyline length, project point → polyline; + M4.4 remainingPolyline(of:from:)
    │       │   ├── RouteProgress.swift         # M4.3 — pure engine: NavigationProgress + NavigationProgressCalculator; + M4.4 remainingDuration(along:)
    │       │   ├── RouteFormatting.swift       # M4.4 — pure RouteFormat (distance / duration / locale-aware clock) + Duration.inSeconds
    │       │   ├── RouteViewModel.swift        # SDK-free: state = idle/loading/loaded(RouteOptions)/…; refresh = none/recalculating/options/… (M4.5 manual + M4.6 automatic reroute — shared field/task, refreshWasAutomatic + cooldown)
    │       │   └── RouteStatusView.swift       # small transient loading/error pill (presentational)
    │       └── Navigation/                     # M4.3–M4.6 — turn-by-turn session, info panel, route-option selector, off-route detection (SDK-neutral)
    │           ├── NavigationViewModel.swift   # @MainActor: start/stop/update/reroute, state, ManeuverCard, routeInfo(now:); owns OffRouteDetector → offRouteStatus + needsAutomaticReroute (M4.6)
    │           ├── ManeuverCard.swift          # presentational model + NavigationDistance formatting
    │           ├── ManeuverCardView.swift      # top-of-map card (arrow + distance + instruction/road + Refresh (M4.5) + End) (presentational)
    │           ├── RouteInfo.swift             # M4.4 — SDK-neutral display model: preview(route:) / remaining(route:progress:) → distance/duration/ETA text + Kind labels
    │           ├── RouteInfoPanelView.swift    # M4.4 — bottom 3-stat panel (distance · time · ETA); preview vs live look (presentational)
    │           ├── RouteOptionsPanelView.swift # M4.5 — compact route-option chips (duration/distance/label); preview selector + nav-refresh selector (presentational)
    │           └── StartNavigationButton.swift # "Start Navigation" action over the route preview (presentational)
    │   # The CarPlay-style shell now lives in Shell/ (M5.0–M5.2.0); the spec's
    │   # "Home/DashboardView" is realised as DashboardShell + Shell/Dashboard/.
    │   # (spec-planned but NOT present: Models/, Features/Music, Features/Speedometer,
    │   #  Features/Settings, Core/ThemeManager)
    ├── DashTests/                   # Swift Testing
    │   ├── LocationReceiverTests.swift
    │   ├── PacketLineBufferTests.swift
    │   ├── LocationStoreTests.swift
    │   ├── ConnectionCoordinatorTests.swift   # first-time pairing, prefer-paired, ignore-stranger, Disconnect vs Forget, friendly-name-at-pairing
    │   ├── ConnectionSetupViewTests.swift     # device-list / "looking for paired" / "Stop Searching" / Forget-<name> mapping
    │   ├── ConnectedControlViewTests.swift    # device-label fallback for the connected overlay
    │   ├── KnownDeviceStoreTests.swift
    │   ├── MapCameraStateTests.swift          # location -> camera transform; MapViewModel basics
    │   ├── MapContentTests.swift              # MapCoordinateBounds math; MapViewModel content/mode/destination derivation
    │   ├── PlaceSearchTests.swift             # PlaceSearchViewModel (debounce/resolve, stub service) + DestinationStore
    │   ├── RouteTests.swift                   # M3–M4.5: Route model, polyline decode, Routes request/response mapping (steps + M4.5 alternatives), RouteViewModel (+ refresh), MapViewModel route options + selection
    │   ├── RouteOptionsTests.swift            # M4.5: RouteOptions construction / selection / alternatives / summaries + relative labels
    │   ├── VehicleIndicatorTests.swift        # M4.1: LocationPacket → VehicleIndicator (heading validation); GoogleMapProvider.vehicleStyle dot/pointer
    │   ├── CameraFollowTests.swift            # M4.2: follow on/off, any user gesture disables (incl. tiny), recenter, navigation plan, UserGestureLatch
    │   ├── NavigationTests.swift              # M4.3: RouteGeometry, progress engine, NavigationViewModel (+ M4.5 reroute), ManeuverCard, nav camera/zoom; + M4.4 remainingPolyline + route-clip rendering + camera anchor
    │   ├── RouteInfoTests.swift               # M4.4: RouteFormat (distance/duration/clock), Duration.inSeconds, remainingDuration, RouteInfo preview/remaining, NavigationViewModel.routeInfo
    │   ├── OffRouteTests.swift                # M4.6: OffRouteDetector classification/hysteresis/re-signal, RouteViewModel.autoReroute (current origin, cooldown, no-concurrency w/ manual), NavigationViewModel off-route signal, reroute adoption
    │   ├── ComponentSizeTests.swift           # M5.0: widgetSizes / isWidget / Codable
    │   ├── ShellStoreTests.swift              # M5.0: ShellSurface (cases/page/Codable) + ShellStore navigation (openApp→closeApp returns to prior surface, space nav, sidebar toggle)
    │   ├── FeatureRegistryTests.swift         # M5.0: lookup, order, duplicateIDs detection, default registry registers Map
    │   ├── MapFeatureTests.swift              # M5.0/M5.1: manifest; app-scoped ownership — presenting MapFullScreenView observes the feature's view models, an active nav session survives re-presentation
    │   ├── DashboardLayoutTests.swift         # M5.2.0: model + identity + Codable round-trip; DashboardGrid spans/bounds/intersects; DashboardLayoutValidator (structural + registry-aware; the shipped starter validates clean)
    │   ├── DashboardLayoutStoreTests.swift    # M5.2.0: default seeding, persistence round-trip, corrupt / wrong-version / structurally-invalid → seed fallback, resetToDefault; DashboardSpaceView page clamp
    │   └── DashTests.swift          # scaffold `example()` — no-op, still present
    ├── DashUITests/                 # Xcode scaffold only, no real tests
    └── DashRelay/                   # iPhone app target
        ├── DashRelayApp.swift       # @main; owns RelaySessionController (@StateObject), renders RelayStatusScreen, starts session in .task
        ├── Info.plist               # UIBackgroundModes:[location], NSLocalNetworkUsageDescription, NSBonjourServices
        ├── Features/Status/
        │   └── RelayStatusView.swift       # RelayStatusScreen (container) + RelayStatusView (presentational): Start / Stop Sharing (waiting) / Disconnect (connected)
        ├── Services/
        │   ├── LocationTracker.swift       # wraps CLLocationManager; wantsTracking gate so auth callbacks can't revive GPS after stop()
        │   ├── LocationBroadcaster.swift   # NWListener advertised via Bonjour WITH a TXT record (relay id + name), \n-delimited JSON to N clients
        │   ├── RelayIdentity.swift         # persists a per-install UUID; builds the RelayAdvertisement (stable id + UIDevice.current.name)
        │   └── RelaySession.swift          # session layer: RelaySessionController (stopped/waiting/connected) + RelayTracking/RelayBroadcasting seams
        └── DashRelayTests/
            ├── LocationTrackerTests.swift
            ├── LocationBroadcasterTests.swift   # now also: advertises identity, service-name fallback
            ├── RelayIdentityTests.swift
            ├── RelaySessionControllerTests.swift
            └── RelayStatusViewTests.swift
```
(`DashRelay/ContentView.swift`, the "Hello, world!" scaffold, was removed when
`RelayStatusScreen` became the root.)

`DashShared` is referenced by the Xcode project as a local Swift package and
linked into `Dash`, `DashTests`, `DashRelay`, and `DashRelayTests`.

### Runtime data flow (as built)

```
iPhone — DashRelay                              iPad — Dash
────────────────────                            ──────────────────
RelayIdentity.load() → RelayAdvertisement        KnownDeviceStore  (persisted [KnownRelay],
  (persisted UUID + UIDevice name)                 keyed by stable relay id)   ← PAIRING
     │ TXT record                                       │  pairedRelay
     ▼                                                  ▼
RelaySessionController (stopped/waiting/          ConnectionCoordinator (disconnected/discovering/
  connected); start() → advertise + track,         connecting/connected); startSession() /
  stop() → stop networking AND GPS                  pairAndConnect(to:) / disconnect() / forgetPairedRelay()
     │                                                  │ owns the transport; picks the target relay
     ▼                                                  ▼
CLLocationManager                                LocationReceiver (NWBrowser "_dashrelay._tcp";
  → LocationTracker.packet(from:)                   reads RelayAdvertisement from each result's TXT record;
  → onPacket (in didUpdateLocations)               onDiscoveryChange → [DiscoveredRelay];
  → LocationBroadcaster.broadcast(_:)              setTargetRelay(id:) → connect to ONE relay,
  → NWListener + Bonjour Service                    reconnect only to it, never to a stranger)
     (name + TXT: rid, name) ───JSON+\n──────────▶ → PacketLineBuffer → onPacket → ConnectionCoordinator
                                                     → LocationStore.ingest(_:)  ← SINGLE SOURCE OF TRUTH (location DATA)
                                                        ├─ @Published latestPacket / signal
                                                        └─ watchdog Task: no packet in staleInterval ⇒ signal = .stale
                                                               │
                                                     RootView: DashboardShell when isConnected
                                                     (sidebar w/ ConnectedControlView: name / Disconnect /
                                                     Forget), else ConnectionSetupView(model:) — device
                                                     picker / "name this iPhone" / "Looking for <paired>…" /
                                                     "Stop Searching" / "Forget <name>"
                                                        → DashboardShell → (Home | DashboardSpaceView |
                                                          MapFeature.makeFullScreenView() → MapFullScreenView
                                                          → DashMapView → MapViewModel → GoogleMapProvider)
```

Connection state (`disconnected/discovering/connecting/connected`) lives **only**
in `ConnectionCoordinator`. `LocationStore` no longer tracks a link phase — it
owns location *data* and the data-freshness watchdog, which is a separate concern
(you can be `.connected` but `signal == .stale` if the relay is up but has no GPS
fix).

**Pairing vs connection stay separate concerns.** *Pairing* is a persisted
relationship (`KnownDeviceStore`, keyed by a relay's stable id). *Connection* is
the transient live session (`ConnectionCoordinator` + `LocationReceiver`). The
coordinator now *reads* `KnownDeviceStore` to decide which relay to target and
*writes* to it on an explicit pair / forget — but persistence logic stays in the
store and transport logic stays in the receiver.

### Key architectural rules currently honoured

- **`LocationStore` is the only consumer of network data.** `LocationReceiver`
  pushes into it; features read from it. Nothing else opens a connection.
- **The shell owns layout + navigation; features own content (M5).** A feature
  is a `DashFeature` (manifest + `makeFullScreenView()` + `makeComponentView(size:)`)
  and never references `Shell/`. `DashboardShell` is the single layout owner and
  never references a Map view model. `MapFeature` is the *only* bridge between
  `Shell/` and Map internals. `FeatureRegistry.makeDefault()` is the one place
  the feature set is declared. See §5 items 33–34.
- **Wire types live in `DashShared`.** `LocationPacket`, `LocationWireFormat`
  (service type + JSON/date strategy + `\n` framing) and now `RelayAdvertisement`
  (the Bonjour TXT-record contract: `rid` + `name`) are defined once. `DashRelay`
  and `Dash` both go through them.
- **Three separate boundaries: render behind `MapProvider`, search behind
  `PlaceSearchService`, routing behind `RouteService`.** `import GoogleMaps`
  appears in exactly two files (`GoogleMapProvider.swift`,
  `GoogleMapsConfiguration.swift`); `import GooglePlaces` in exactly two
  (`GooglePlaceSearchService.swift`, `GooglePlacesConfiguration.swift`). **No
  routing file imports any SDK at all** — `GoogleRouteService` calls the Routes
  API over `URLSession` and imports only Foundation. Every other Map / Search /
  Routing file is SDK-free. `MapProvider` is **rendering only** (a `MapContent`
  value in, a `MapEvent` closure back) — it has no search / routing / place
  methods. Place search lives on the **`PlaceSearchService` protocol** (M2);
  route computation on the **`RouteService` protocol** (M3, `route(from:to:)`
  taking plain `MapCoordinate`s) — so a MapKit provider could back either with
  `MKLocalSearch` / `MKDirections` without touching the renderer. The chosen
  destination (`Destination`) is held in `DestinationStore`; the computed
  `Route` is SDK-neutral (polyline + distance + `Duration`).
- **The map receives state as input, emits events as output.** `MapViewModel`
  holds no `LocationStore` reference, no networking, no GPS. It converts a
  `LocationPacket` into a follow `MapCameraState` (pure `following(_:)`), assembles
  the full `MapContent` (camera plan + vehicle + overlays) for the active
  `MapMode`, and routes `MapEvent`s back. As of M3 `MapContent.markers` (the
  destination pin) and `MapContent.polylines` (the route, via `setRoute(_:)`)
  are both populated; `MapEvent` consumption still awaits navigation.
  `setRoute(_:)` re-fits the `.destinationPreview` camera **once**, around
  vehicle + destination + route, so the whole route is visible — a later fix
  still does not move it (that would be navigation camera behaviour, deferred).
- **Bonjour discovery, never a hardcoded IP** — on both sides.
- **The receiver connects to ONE identified relay, not "results.first".**
  `LocationReceiver` browses continuously, reports every visible relay via
  `onDiscoveryChange`, and only opens a connection once `ConnectionCoordinator`
  names a target with `setTargetRelay(id:)`. After an incidental drop it
  re-browses and reconnects **only to that same relay id** — a different relay
  appearing nearby is never picked up silently.
- **Incidental disconnects are routine.** The receiver re-browses and reconnects
  to the target on a timer; `LocationStore`'s watchdog covers the UI gap. A
  **deliberate** disconnect is different — it stays disconnected (see below).
- **SwiftUI + MVVM**, `@MainActor` isolation, serial-queue-confined
  `@unchecked Sendable` classes for the Network-framework wrappers.

### Connection / session layer

A thin layer that sits **above** the networking and location layers — it does
not replace their responsibilities.

**Three separate concerns, three types:**

| Concern | Type | Owns |
|---|---|---|
| Current connection state + session lifecycle (iPad) | `ConnectionCoordinator` (`@MainActor ObservableObject`) | the `LocationReceiving` transport; `@Published connectionState` / `connectedRelayID` / `connectedDisplayName` / `discoveredRelays`; derived `pairedRelayName` / `pairedRelayDisplayName` / `offerableRelays`; `startSession()` / `pairAndConnect(to:named:)` / `disconnect()` / `forgetPairedRelay()` |
| Current session state (iPhone) | `RelaySessionController` (`@MainActor ObservableObject`) | `LocationTracker` + `LocationBroadcaster`; `@Published state` (`stopped`/`waiting`/`connected`) / `isTrackingLocation`; `start()` / `stop()` |
| Pairing / known devices (iPad) | `KnownDeviceStore` (`@MainActor ObservableObject`) | a persisted `[KnownRelay]` (keyed by stable relay id) with `remember` / `forget` / `forgetAll` / `pairedRelay` |

- **`ConnectionCoordinator` owns the transport lifecycle**, not `LocationStore`.
  It translates `LocationReceiver.Status.Phase` → `ConnectionState`
  (`stopped→disconnected`, `browsing→discovering`, `connecting→connecting`,
  `connected→connected`), forwards decoded packets into `LocationStore.ingest(_:)`
  (still the only place packets land), and calls `LocationStore.connectionEnded()`
  on a deliberate disconnect.
- **`LocationReceiver` / `LocationBroadcaster` keep their jobs.** Discovery +
  receiving stays in `LocationReceiver`; advertising + sending stays in
  `LocationBroadcaster`. The session layer only decides *when* they run.
- **Deliberate disconnect ≠ auto-reconnect.** `ConnectionCoordinator.disconnect()`
  sets a `deliberatelyDisconnected` flag, calls `receiver.stop()` (which clears
  the receiver's own `isActive` so its reconnect loop is inert), and ignores any
  trailing transport status. `RelaySessionController.stop()` stops both the
  broadcaster and the tracker and lands in `.stopped`, from which nothing
  restarts on its own.
- **The relay session controls GPS.** `RelaySessionController.start()` starts
  `LocationTracker`; `.stop()` stops it. `LocationTracker` also gained a
  `wantsTracking` gate so a late Core Location authorization callback can't
  re-`startUpdatingLocation()` after a deliberate stop.
- **The dashboard is gated.** `RootView` shows `DashboardShell` (the M5 shell)
  only when `ConnectionCoordinator.isConnected`; otherwise `ConnectionSetupView`.
  The shell (and the map) is never shown without an active connection. `RootView`
  is the only place that reads connection state for gating; `DashboardShell` and
  feature views never see it. Both connection views are presentational and hold
  no copy of the connection/pairing state:
  - `ConnectionSetupView` takes `ConnectionSetupView.Model` (state +
    `offerableRelays` + `pairedRelayName`) and closures (`onPair`, `onForget`,
    `onStopSearching`, `onSearch`). Its one bit of local state is the "name this
    iPhone" alert (presentation only).
  - `ConnectedControlView` (M5.0 moved it into `SidebarView`; `DashboardShell`
    wires its closures to `ConnectionCoordinator`) takes the paired device name +
    `onDisconnect` / `onForget` closures. Its one bit of local state is the
    confirmation dialog.
- **Pairing flow (iPad).** First launch: browse → if ≥1 relay is visible and
  nothing is paired, `ConnectionSetupView` lists them; the user taps one, is
  prompted to **name** it, and confirms → `ConnectionCoordinator.pairAndConnect(to:named:)`
  → `KnownDeviceStore.remember(KnownRelay(id:, displayName: <friendly name>))`
  **and** `receiver.setTargetRelay(id:)`. The friendly name is display-only;
  blank falls back to the advertised name; the stable `id` is never touched by
  it. Later launches: `startSession()` targets the paired relay immediately; if
  it isn't visible the screen says "Looking for <name>…" and never offers a
  nearby stranger. `forgetPairedRelay()` removes the `KnownRelay`, clears the
  transport target (dropping the session if it was to that relay), and returns
  to first-time browsing.
- **Disconnect vs Forget, reachable from both apps.** On the iPad,
  `ConnectionSetupView` offers **"Stop Searching"** (deliberate, sticky — via
  `disconnect()`) while browsing/connecting, and `ConnectedControlView` offers
  **Disconnect** (ends the session, keeps the pairing) and **Forget <name>**
  (drops the pairing) while connected. On the iPhone, `RelayStatusView` offers
  **"Stop Sharing"** while `.waiting` and **Disconnect** while `.connected` —
  both call `RelaySessionController.stop()`, so the relay never has to be left
  advertising indefinitely.
- **DashRelay shows its session state.** `RelayStatusScreen` (the DashRelay root)
  reads `RelaySessionController` from the environment and hands `state` + an
  `onStart` / `onStop` pair to the presentational `RelayStatusView`
  (`stopped` → Start, `waiting` → "Ready to Connect" + spinner + **"Stop
  Sharing"**, `connected` → **Disconnect**). "Stop Sharing" and "Disconnect"
  both call `RelaySessionController.stop()`; the view contains no networking or
  GPS logic and keeps no copy of the state.
- **Pairing state is a distinct concern, but now bridged.** `KnownDeviceStore` is
  still storage-only (no networking). `ConnectionCoordinator` now holds a
  reference to it (`any KnownDeviceStoring`, injected) so it can prefer the paired
  relay and persist an explicit pair/forget — superseding the earlier "hold no
  reference to each other" arrangement (see §5 decision 15). `KnownRelay` is keyed
  by the relay's **stable id** from the TXT record (not the Bonjour service name);
  the store still supports multiple devices, with `pairedRelay` = the first for
  now.

---

## 3. Implemented and verified functionality

### DashShared

- **[Implemented]** `LocationPacket` — `Codable, Equatable, Sendable`; fields
  `latitude`, `longitude`, `speed`, `heading` (`Double`), `timestamp` (`Date`).
  `speed`/`heading` keep `CLLocation`'s "negative = invalid" semantics.
- **[Implemented]** `LocationWireFormat` — shared `bonjourServiceType`
  (`"_dashrelay._tcp"`), `makeEncoder()`/`makeDecoder()` (ISO-8601 dates),
  `lineDelimiter` (`\n`), `encodeLine(_:)`.
- **[Implemented]** `RelayAdvertisement` — the Bonjour TXT-record contract for
  pairing: `id` (stable relay identity, key `rid`) + `displayName` (key `name`).
  `txtRecordEntries` for the relay to publish; `init?(txtRecordEntries:)` for the
  dashboard to read back (returns `nil` without a non-empty `id`).
- **[Verified · automated]** `LocationPacketTests` (4) + `RelayAdvertisementTests`
  (4): JSON round-trip, invalid-fix sentinels survive, fixed payload, exact key
  set; TXT round-trip, exact keys, missing/empty `id` rejected, missing name → "".

### DashRelay (iPhone)

- **[Implemented]** `LocationTracker` — wraps `CLLocationManager`
  (`kCLLocationAccuracyBestForNavigation`, `.automotiveNavigation`,
  `pausesLocationUpdatesAutomatically = false`), requests **Always**
  authorization, sets `allowsBackgroundLocationUpdates` when granted, converts
  each `CLLocation` to a `LocationPacket`, and calls `onPacket` synchronously
  inside `didUpdateLocations`. A `wantsTracking` gate (set only by
  `start()`/`stop()`) means a late authorization callback cannot revive GPS
  after a deliberate stop; a `denied`/`restricted` change stops delivery without
  clearing intent, so re-granting permission resumes.
- **[Implemented]** `LocationBroadcaster` — `NWListener` advertised as a Bonjour
  `_dashrelay._tcp` service **with a TXT record** carrying this relay's
  `RelayAdvertisement` (`rid` + `name`), so the iPad can pair with *this* iPhone
  specifically. Accepts multiple concurrent TCP clients; sends each packet as one
  `\n`-terminated JSON line; clean connect/disconnect handling; a main-actor
  `onStatusChange` hook (`isListening`, `clientCount`). The Bonjour instance name
  is the device name (or `"DashRelay"` when empty) — user-facing, not the pairing
  key.
- **[Implemented]** `RelayIdentity` — mints a random UUID on first use, persists
  it in `UserDefaults`, and returns a `RelayAdvertisement` pairing it with
  `UIDevice.current.name`. The identity lives for the life of the install; a
  rename keeps it, a reinstall replaces it (re-pair once).
- **[Implemented]** `RelaySessionController` — the iPhone session layer. Owns
  `LocationTracker` + `LocationBroadcaster` behind `RelayTracking` /
  `RelayBroadcasting` seams; wires each fix straight through;
  `@Published state` (`stopped` / `waiting` / `connected`, derived from
  `clientCount`) and `isTrackingLocation`; `start()` begins advertising + GPS,
  `stop()` (deliberate disconnect) stops both; nothing auto-restarts from
  `.stopped`.
- **[Implemented]** `DashRelayApp` owns `RelaySessionController` as `@StateObject`,
  renders `RelayStatusScreen`, and calls `session.start()` in `.task` at launch.
- **[Implemented]** `RelayStatusScreen` / `RelayStatusView` (`Features/Status/`) —
  the DashRelay connection/status UI. `RelayStatusScreen` is the container
  that reads `RelaySessionController` (single source of truth) from the
  environment; `RelayStatusView` is presentational — it takes the `State` plus
  an `onStart` / `onStop` pair and holds no copy of the state. Screens:
  a **startup screen** (`stopped` → "Relay Stopped" + a **Start** button that
  calls `session.start()`); a **waiting screen** (`waiting` → "Ready to Connect"
  + spinner + a **"Stop Sharing"** button so the relay isn't left advertising
  forever); and a **connected screen** (`connected` → "Connected" + a
  **Disconnect** button). "Stop Sharing" and "Disconnect" both call
  `RelaySessionController.stop()` (→ `.stopped`). The connected screen shows a
  **generic
  message** — it does **not** display the connected Dash device's name, because
  `RelaySessionController` does not expose a client name yet (`LocationBroadcaster`
  only reports `clientCount`). A nested `RelayStatusView.Display` value type does
  the pure `State` → screen mapping (symbol, title, message, `showsActivity`,
  action). Layout mirrors `ConnectionSetupView` (`GeometryReader` + `ScrollView`,
  centred, `maxWidth: 460`) — responsive across iPhone orientations. **No pairing
  controls.** Visuals are intentionally plain.
- **[Implemented]** `Info.plist` — `UIBackgroundModes: [location]`,
  `NSLocationAlwaysAndWhenInUseUsageDescription`,
  `NSLocationWhenInUseUsageDescription`, `NSLocalNetworkUsageDescription`,
  `NSBonjourServices: [_dashrelay._tcp]`.
- **[Verified · automated]** `LocationTrackerTests` (7): field mapping, speed
  stays raw m/s, negative speed/course preserved, JSON round-trip, manager
  configuration, initial state.
- **[Verified · automated]** `LocationBroadcasterTests` (7): service type,
  single-`\n` framing, line decodes back, multi-line stream splits, lifecycle
  no-ops, **advertises the relay identity**, **service-name falls back to
  `"DashRelay"` when the device name is empty**.
- **[Verified · automated]** `RelayIdentityTests` (4): mints an id on first use
  and reuses it, distinct id per install (per store), device name flows through
  as the display name, **a rename keeps the same identity**.
- **[Verified · automated]** `RelaySessionControllerTests` (8): `stopped→waiting`
  on `start()` (advertising + GPS begin), `waiting→connected` when a client
  attaches and back, `connected→stopped` on `stop()` (broadcaster + tracker
  stopped), **stopping the session stops tracking**, **a deliberate disconnect
  does not immediately reconnect** (trailing status ignored), resume after stop,
  fixes forwarded to the broadcaster.
- **[Verified · automated]** `RelayStatusViewTests` (6): the `Display` `State` →
  screen mapping — `stopped` offers *Start* with no activity indicator; `waiting`
  shows the activity indicator and offers **"Stop Sharing"**; `connected`
  offers *Disconnect* with no activity indicator; every state has non-empty
  title/message/symbol; **Disconnect is offered only when connected**.
- **[Verified · simulator]** `RelayStatusView` was rendered on the iPhone
  simulator in the `waiting` state (portrait and landscape): antenna symbol,
  "Ready to Connect", spinner, explanatory text; content stays centred and
  width-capped. **This predates the "Stop Sharing" button** — that button and
  the updated wording have not been re-rendered on a real screen this round
  (covered by the `Display` unit tests).
- **[Implemented]** DashRelay app builds and launches; the root is now
  `RelayStatusScreen`.

### Dash (iPad)

- **[Implemented]** `LocationReceiver` — `NWBrowser` for `_dashrelay._tcp`. Reads
  each result's TXT record into a `RelayAdvertisement` and reports the visible set
  via `onDiscoveryChange → [DiscoveredRelay]`. **Connects only to the relay named
  by `setTargetRelay(id:)`** — never "results.first" — and after an *incidental*
  drop re-browses and reconnects **only to that same id** (suppressed after a
  deliberate `stop()`, which also clears the target). `Status` phases
  `stopped / browsing / connecting / connected` plus `connectedRelayID` /
  `connectedDisplayName` via a main-actor `onStatusChange`. Conforms to
  `LocationReceiving`. *(Bonjour/TCP internals remain device-validated, not unit
  tested — see below.)*
- **[Implemented]** `PacketLineBuffer` — reassembles the TCP byte stream, splits
  on `\n`, decodes each line, keeps partial trailing lines, skips blank/malformed
  lines, drops the buffer if an unterminated line exceeds 64 KB.
- **[Implemented]** `LocationStore` — `@MainActor ObservableObject`, the single
  source of truth **for received location data**: `@Published latestPacket /
  signal`; derived `hasFix / isSignalLost / speed / heading`; `ingest(_:)`
  records a packet and arms the watchdog; watchdog `Task` sleeps `staleInterval`
  (default 7 s, in the spec's 5–10 s band) then flags `.stale` while keeping the
  last packet; `refreshSignal(now:)` for deterministic tests; `connectionEnded()`
  returns to `.waiting` when the session stops. **No longer owns the transport or
  a link phase** — that moved to `ConnectionCoordinator`.
- **[Implemented]** `ConnectionCoordinator` — the iPad session + pairing-bridge
  layer. Owns a `LocationReceiving` and a `KnownDeviceStoring`; `@Published`
  `connectionState` (`disconnected` / `discovering` / `connecting` / `connected`),
  `connectedRelayID`, `connectedDisplayName`, `discoveredRelays`; computed
  `offerableRelays` (empty once paired) and `pairedRelayName`. Actions:
  `startSession()` (browse + target the paired relay), `pairAndConnect(to:)`
  (remember + target — first-time pick), `disconnect()` (deliberate, sticky,
  keeps pairing), `forgetPairedRelay()` (remove the `KnownRelay`, clear the
  target, drop the session if it was to that relay, resume browsing). Auto-connect
  fires **only** when exactly one *known* relay is visible; a stranger is never
  targeted. Pure `connectionState(for:)` phase mapping.
- **[Implemented]** `KnownDeviceStore` — `@MainActor ObservableObject` +
  `KnownDeviceStoring`; a `[KnownRelay]` **keyed by the relay's stable id**
  (`RelayAdvertisement.id`) persisted as JSON in `UserDefaults`;
  `remember` / `forget` / `forgetAll` / `isKnown(id:)` / `pairedRelay` (first
  known). Still **storage only** — no networking; the coordinator decides *when*
  to call `remember` / `forget`.
- **[Implemented]** `RootView` — gates the UI: when connected, `DashboardShell`
  (the M5 CarPlay-style shell — §5 items 33–34); otherwise `ConnectionSetupView`.
  Builds the setup screen's `Model` from the coordinator and wires every action
  (`disconnect` / `startSession` / `pairAndConnect(to:named:)` /
  `forgetPairedRelay`). While connected, `DashboardShell` wires
  `ConnectedControlView`'s Disconnect / Forget back to the coordinator.
- **[Implemented]** `ConnectionSetupView` (`Features/Connection/`) — the
  connection/setup + **pairing** screen, shown whenever Dash is not connected.
  Presentational: takes `ConnectionSetupView.Model` (state + `offerableRelays` +
  `pairedRelayName`) and closures (`onPair`, `onForget`, `onStopSearching`,
  `onSearch`) — no store, no network. One bit of local state: the "name this
  iPhone" alert. Renders:
  - **first-time, nothing paired, ≥1 relay visible** → a tappable **device list**
    (name + short id); tapping opens an alert with a text field pre-filled with
    the advertised name → `onPair(relay, name)` pairs (with the friendly name)
    and connects;
  - **paired but relay not visible** → spinner + "Looking for `<name>`…", never a
    stranger in the list;
  - *discovering (nothing yet)* / *connecting* → spinner + status; *disconnected*
    → **Search for DashRelay**; **Stop Searching** whenever a live attempt exists
    (wired to `disconnect()` — deliberate/sticky);
  - a **"Forget `<name>`"** button whenever a device is paired.
  Nested `ConnectionSetupView.Display` does the pure `Model` → screen mapping
  (incl. `forgetLabel`). Layout unchanged (`GeometryReader` + `ScrollView`,
  centred, `maxWidth: 460`) — iPad portrait + landscape and iPhone. Visuals
  still intentionally plain.
- **[Implemented]** `ConnectedControlView` (`Features/Connection/`) — a compact
  pill shown **in the shell sidebar** while connected (M5.0 moved it there from
  the old `RootView` overlay). Shows the paired iPhone's friendly name
  (`ConnectionCoordinator.pairedRelayDisplayName`, falling back to "DashRelay")
  and, via a confirmation dialog, **Disconnect** (ends the session, keeps the
  pairing → `disconnect()`) and **Forget `<name>`** (drops the pairing →
  `forgetPairedRelay()`). Presentational; only local state is the dialog. Does
  **not** touch the shell content or the map.
- **[Implemented]** `DashApp` owns `LocationStore`, `KnownDeviceStore`,
  `ConnectionCoordinator`, `FeatureRegistry` (`.makeDefault()`), and
  `DashboardLayoutStore` (seeded `.starter(featureID: MapFeature.id)`) as
  `@StateObject`s, injects them all as `environmentObject`s, calls
  `connection.startSession()` in `.task`, and `GoogleMapsConfiguration.bootstrap()`
  / `GooglePlacesConfiguration.bootstrap()` in `init()` (before the registry so
  `MapFeature`'s SDK-backed services are constructed after the keys are set).
- **[Implemented]** Map abstraction (widened in the "M1" pass — see §5 item 24):
  - `MapProvider` — **rendering-only** protocol: `id` +
    `makeMapView(content: MapContent, onEvent: @escaping (MapEvent) -> Void) -> AnyView`.
    No search / routing / place methods, by design.
  - `MapGeometry` — `MapCoordinate` and `MapCoordinateBounds` (`init?([MapCoordinate])`
    → tightest box; `center`).
  - `MapCameraState` — value type (lat/lon/`headingDegrees?`/zoom + `.default` +
    `following(_:)` + `center`). `MapCameraPlan` — `.follow(MapCameraState)` /
    `.fit(MapCoordinateBounds, padding:)` (route preview) /
    `.navigation(MapCameraState, pitchDegrees:, vehicleVerticalAnchor:)` (M4.2,
    tuned M4.4 — a tilted framing that puts the vehicle at `anchor` of the
    viewport height from the top, `> 0.5` = slightly below centre; the provider
    turns the anchor into its own viewport padding).
  - `MapContent` — the full render state: `camera: MapCameraPlan`,
    `vehicle: VehicleIndicator` (M4.1 — was a bare `MapCoordinate`),
    `polylines: [MapPolyline]`, `markers: [MapMarker]`. `Equatable` for provider-side diffing.
  - `VehicleIndicator` (M4.1) — SDK-neutral current-location: `coordinate` +
    `headingDegrees: Double?`. `init(_ packet: LocationPacket)` validates the
    heading (negative / NaN → `nil`, matching `MapCameraState.following`). Kept
    apart from `MapMarker` so a provider styles it navigation-style, not as a pin.
  - `MapOverlay` — `MapPolyline` (`id` + `coordinates` + **`role`**:
    `.selected` / `.alternative`, M4.5) and `MapMarker` (`id` + `coordinate` +
    `title?`), both `Identifiable`. (The vehicle indicator is deliberately *not*
    here — exactly one per render.)
  - `MapEvent` — `.tappedMap` / `.tappedPOI(MapPOI)` / `.tappedMarker(id:)` /
    **`.tappedRoute(id:)`** (M4.5 — pick an alternative from the map, preview
    only) / `.cameraIdle(MapCameraPosition, byUserGesture:)`. As of M4.2
    `byUserGesture` is `true` for **any** user pan/zoom/rotate gesture — however
    small — and `false` for programmatic camera moves. No distance/zoom threshold.
  - `MapMode` — `cruising` / `destinationPreview` / `navigating`. All three have
    realised camera framing. `MapViewModel.startNavigation()` (M4.3) drives the
    app into `.navigating` from the route preview. Guidance layered on since:
    maneuver card + dynamic zoom (M4.3), ETA / route-clip (M4.4), route options /
    refresh (M4.5), off-route detection + automatic rerouting (M4.6). Voice /
    lane guidance / traffic-aware ETA remain out of scope.
  - `MapViewModel` — holds `any MapProvider` + `mode` + retained `camera` +
    `destination` + `route` (the *active* route) + **`routeOptions`** (M4.5, the
    choices + selection) + **`followsVehicle`** (M4.2) +
    **`navigationProgress`** (M4.3, mirrored from `NavigationViewModel`).
    `update(with:)` always moves the `VehicleIndicator`; it re-derives the
    rendered camera **only** in `.cruising` / `.navigating` while `followsVehicle`
    is on. `handle(.cameraIdle(_, byUserGesture: true))` in a follow mode →
    `followsVehicle = false` (+ remembers the user's zoom); programmatic idles are
    ignored (no feedback loop). **`recenter()`** re-arms follow and snaps to the
    vehicle with the mode's plan; a deliberate mode change (`setMode` /
    `setDestination`) also re-arms it. `showsRecenterButton` = follow off in a
    follow mode. `.destinationPreview` is untouched by M4.2/M4.3.
    **M4.3:** `startNavigation()` (gated on `canStartNavigation` — preview mode +
    a route + `hasReceivedFix`) resets to `navigationBaseZoom` and enters
    `.navigating`; `setNavigationProgress(_:)` feeds live maneuver progress in and
    re-derives the camera. The `.navigating` follow camera keeps the M4.2
    tilt/below-centre framing but overrides the zoom via the pure
    `navigationZoom(base:distanceToManeuverMeters:approachingSignificantManeuver:)`
    — base until ~350 m from a `warrantsCloserView` maneuver, ramping to
    `base + 1.5` by ~40 m, quantised to 0.5 steps; eases back to base once past
    the turn. When `followsVehicle` is off, progress updates never move or zoom
    the camera.
    **M4.4:** the `.navigating` plan carries `vehicleVerticalAnchor = 0.6` (the
    vehicle sits slightly below centre — it was previously pushed above centre).
    `rebuildRoutePolylines()` (called from `update` / `setMode` / `setRouteOptions`
    / `selectRouteOption` / `setDestination`) sets `content.polylines`: the active
    `route` as `.selected`, clipped to
    `RouteGeometry.remainingPolyline(of: route.polyline, from: vehicle)` while
    `.navigating` (else the whole route), plus every other `routeOptions` route
    as `.alternative`. `route` and its `polyline` are never mutated.
    **M4.5:** `setRouteOptions(_:)` — in preview the selected option becomes
    `route` and the camera re-fits; while `.navigating` a *refreshed* set draws
    as alternatives and `route` (the route being driven) is left alone.
    `selectRouteOption(_ id:)` — preview: the pick becomes `route`, camera
    re-fits, **navigation is not started**; navigation: adopts the pick as
    `route`, resets `navigationProgress`, and only moves the camera if follow is
    on. `handle(.tappedRoute)` selects an alternative from the map in preview
    (ignored while navigating). `setRoute(_:)` is a one-route convenience over
    `setRouteOptions`.
  - `DashMapView` — neutral component; feeds `location` in, forwards `MapEvent`s,
    and overlays `RecenterButton` (bottom-trailing) when `showsRecenterButton`.
  - `RecenterButton` (M4.2) — a small presentational circular button; `DashMapView`
    owns its visibility and wires the tap to `viewModel.recenter()`. Not in the
    provider.
- **[Implemented]** Destination search (M2 — see §5 item 25):
  - `Destination` / `PlaceSuggestion` — SDK-neutral value types (`placeID`,
    name, address?, `MapCoordinate` / primary+secondary text).
  - `PlaceSearchService` — provider-neutral `@MainActor` protocol:
    `suggestions(matching:near:) async throws -> [PlaceSuggestion]` and
    `details(for placeID:) async throws -> Destination`; `PlaceSearchError`
    (`placeNotFound` / `unavailable`). **Separate from `MapProvider`.**
  - `GooglePlaceSearchService` — the only Search file importing `GooglePlaces`.
    Autocomplete (`GMSAutocompleteRequest` / `fetchAutocompleteSuggestions`) +
    Place Details New (`GMSFetchPlaceRequest` / `fetchPlace`), one lazily-minted
    `GMSAutocompleteSessionToken` per search run (cleared after `details`),
    location bias around the vehicle. Maps GMS errors to `PlaceSearchError`.
  - `DestinationStore` — `@MainActor ObservableObject`, the source of truth for
    the chosen `Destination?` (`select` / `clear` / `hasDestination`).
  - `PlaceSearchViewModel` — SDK-free orchestration: `@Published query` with a
    debounced lookup (`runSearch` is the testable core), `suggestions` /
    `isSearching` / `errorText`, `origin` for biasing, `choose(_:)` → `resolve`
    → `onDestinationChosen(Destination)`; `reset()`.
  - `MapSearchView` — a custom SwiftUI search field + suggestions list, and a
    compact chip (name / address / clear button) once a destination is chosen.
    Presentational; no SDK, no map, no store.
  - `MapFullScreenView` (was `ContentView` until M5.1) — the composition point.
    The five view models (`MapViewModel`, `PlaceSearchViewModel`,
    `DestinationStore`, `RouteViewModel`, `NavigationViewModel`) are **owned by
    `MapFeature`** (app-scoped, M5.1) and only *observed* here; this view wires
    them together and runs the `LocationStore` fix pump while on screen. Wiring:
    `searchVM.onDestinationChosen → destinationStore.select` (this one moved to
    `MapFeature.init`),
    `destinationStore.destination → mapVM.setDestination` + `routeVM.requestRoutes`
    (+ `navVM.stop()`), `routeVM.state (.loaded) → mapVM.setRouteOptions`, the
    vehicle coordinate → `searchVM.origin` / routing origin / `navVM.update` →
    `mapVM.setNavigationProgress`, the Start Navigation tap →
    `mapVM.startNavigation()` + `navVM.start(...)`. **M4.5:**
    `routeVM.refresh (.options) → mapVM.setRouteOptions` (draw the refreshed set),
    a route-option tap → `mapVM.selectRouteOption` (preview) or
    `navVM.reroute` + `mapVM.selectRouteOption` + `routeVM.clearRefresh` (adopt a
    refreshed route mid-drive), the maneuver card's Refresh tap →
    `routeVM.refreshRoutes(from: currentOrigin)`. **M4.6:** after
    `navVM.update(with:)`, if `navVM.needsAutomaticReroute` →
    `navVM.clearRerouteRequest()` + `routeVM.autoReroute(from: currentOrigin)`;
    `routeVM.refresh (.options)` with `refreshWasAutomatic` → `adoptAutomaticReroute`
    (`navVM.reroute` + `mapVM.setRouteOptions` + `mapVM.selectRouteOption(recommended)`
    + `mapVM.setNavigationProgress` + `routeVM.clearRefresh`), else the M4.5
    offer path. A small **"Recalculating…"** pill (bound to
    `routeVM.isAutomaticallyRecalculating`, snap-in transition) shows under the
    maneuver card for the whole automatic request, becoming "Couldn't
    recalculate — keeping current route" on failure. A bottom `TimelineView`
    overlay (ETA stays current) shows the `RouteOptionsPanelView` +
    `RouteInfoPanelView` (M4.4 preview row unchanged) / live panel. The
    components don't know each other.
- **[Implemented]** Routing (M3 — item 26) + turn-by-turn (M4.3 — item 29) +
  route info / ETA (M4.4 — item 30) + multiple routes / refresh (M4.5 — item 31)
  + off-route detection / auto-reroute (M4.6 — item 32):
  - `Route` — SDK-neutral: **`id`** (M4.5, `"route-<index>"` from the provider),
    `polyline`, `distanceMeters`, `duration: Duration`, and **`steps: [RouteStep]`**
    (M4.3; `[]` without step data).
  - `RouteStep` (M4.3) — SDK-neutral maneuver: `ManeuverType` (turn/uturn/ramp/
    fork/roundabout/merge/straight/depart/arrive/nameChange/unknown, each with a
    `phrase`, an SF Symbol, and `warrantsCloserView`), `instruction`,
    `roadName?`, `maneuverPoint`, `polyline`, `distanceMeters`.
  - `RouteOptions` (M4.5) — SDK-neutral: a non-empty `routes: [Route]` (`[0]`
    recommended), a `selectedID`, `selected` / `recommended` / `alternatives` /
    `hasAlternatives`, `selecting(_ id:)`, and `summaries` — one
    `RouteOptionSummary` per route (formatted duration + distance + a relative
    label: "Recommended" / "3 min faster" / "5 min longer" / "Similar time").
  - `RouteService` — provider-neutral `@MainActor` protocol:
    `routes(from:to:) async throws -> [Route]` (M4.5 — `[0]` recommended, never
    empty on success); `RouteError` (`noRoute` / `unavailable`). **Separate from
    `MapProvider` and `PlaceSearchService`.**
  - `GoogleRouteService` — the Google **Routes API** (`POST
    routes.googleapis.com/directions/v2:computeRoutes`, `TRAFFIC_UNAWARE` DRIVE,
    **`computeAlternativeRoutes: true`** (M4.5), encoded-polyline). **Imports
    Foundation only — no GMS types**; `URLSession` injected for tests; reuses
    `GoogleMapsConfiguration.apiKey` (`nonisolated`). Missing key / transport
    error / non-2xx (403 = API not enabled) → `.unavailable`; no usable route →
    `.noRoute`. `parseRoutes(from:)` maps **every** route in the response, in
    order, keyed `"route-<index>"`, dropping ones with < 2 points. The field
    mask asks for `routes.legs.steps.{navigationInstruction,polyline,
    startLocation,endLocation,distanceMeters}`; private `Decodable` DTOs and the
    Google `Maneuver` → `ManeuverType` mapping + the "onto/on/toward" road-name
    heuristic all stay inside this file. Step fields bill at the Routes
    **Advanced** SKU; alternatives do not change the tier (still free-tier for
    one user calling once per trip + one manual refresh — see §5/§9).
  - `GooglePolyline.decode(_:)` — pure encoded-polyline decoder.
  - `RouteGeometry` (M4.3) — pure geodesic helpers: haversine `distance`,
    polyline `length`, `project(_:onto:)` (closest point + distance-from-input +
    distance-along, via a local equirectangular frame), and **M4.4**
    `remainingPolyline(of:from:)` — the part of a polyline still ahead of a point
    (projection onward), `[]` once past the end.
  - `NavigationProgress` / `NavigationProgressCalculator` (M4.3) — the pure
    progress engine. Progress is one scalar `traveledMeters` along the
    concatenated step geometry; `stepIndex` is the upcoming maneuver,
    `distanceToManeuverMeters` / `distanceRemainingMeters` derived. `next(...)`
    only moves forward, advances the displayed maneuver by **at most one per
    fix** (`oneManeuverCap`), and **ignores a fix more than ~80 m off every
    step** so noise can't skip turns. No off-route detection / rerouting.
  - `NavigationViewModel` (M4.3) — `@MainActor`, mirrors the M3 `RouteViewModel`
    pattern (SDK-free, no `LocationStore`). `start(route:from:)` / `stop()` /
    `update(with:)` / **`reroute(to:from:)`** (M4.5 — swap the route mid-drive,
    re-seed progress from the current position, session kept); `state` =
    `inactive` / `navigating(NavigationProgress)` / `arrived`; builds the
    `ManeuverCard`. **M4.4:** `routeInfo(now:)` → the live `RouteInfo` (`nil`
    when inactive or arrived). **M4.6:** owns an `OffRouteDetector`, feeds it
    every fix from `update(with:)`, and exposes `offRouteStatus` +
    `needsAutomaticReroute` (once per episode; `clearRerouteRequest()` after the
    view acts). `start` / `reroute` / `stop` re-arm the detector.
  - `OffRouteDetector` (M4.6) — pure, SDK-neutral. `record(position:on:)` snaps
    the fix onto `route.polyline` via `RouteGeometry.project` and classifies it
    `onRoute` (≤ `onRouteToleranceMeters` **20**) / `possiblyOffRoute` /
    `confirmedOffRoute`. Named conservative thresholds: a hysteresis band up to
    `offRouteThresholdMeters` (**35**) where a fix neither confirms nor clears;
    `confirmationFixCount` (**3**) consecutive meaningful off-route fixes to
    confirm — so one or two noisy fixes never trigger; `resignalAfterFixes` (8)
    before it re-asks for a still-unresolved episode (covers a request the
    coordinator dropped for cooldown). (Tightened from 40 / 70 / 4 after a
    physical drive, 2026-09-03.) Rejoining (≤ tolerance) ends the episode and
    re-arms; `reset()` re-arms explicitly.
  - `NavigationProgress.remainingDuration(along: route)` (M4.4) — pure: scales
    `route.duration` by the fraction of `distanceRemainingMeters` left (no
    traffic model), `.zero` on arrival or a zero-length route. Keeps the ETA
    consistent with the distance shown; never re-derives the route.
  - `RouteFormat` (M4.4) — pure SDK-neutral formatters: `distance(meters:)`
    ("40 m" / "1.4 km" / "23 km"), `duration(_:)` ("< 1 min" / "8 min" /
    "1 hr 15 min"), `time(_:locale:timeZone:)` (a locale/time-zone-aware clock
    string via `Date.FormatStyle`; both injectable, default to the viewer's).
    Plus `Duration.inSeconds`. Deliberately separate from the maneuver-countdown
    `NavigationDistance` (that one has a "Now" band).
  - `RouteInfo` (M4.4) — the SDK-neutral panel model. `.preview(route:now:…)` →
    whole-route distance + duration, ETA = now + duration. `.remaining(route:
    progress:now:…)` → `progress.distanceRemainingMeters` + `remainingDuration`,
    ETA = now + that. `Kind` (`.preview` / `.remaining`) carries the distinct
    column labels. Reuses `Route` + `NavigationProgress` — no duplicate maths.
  - `RouteInfoPanelView` (M4.4) — presentational bottom panel: three stats
    (distance · time · ETA). The `.remaining` variant is blue-accented and
    labelled "Remaining / Time left / ETA"; the `.preview` variant is plain
    material, "Distance / Time / Arrival".
  - `RouteViewModel` — SDK-free, holds no `LocationStore`. `requestRoutes(to:from:)`
    takes the chosen `Destination?` + the latest origin, exposes
    `state` (`idle` / `loading` / **`loaded(RouteOptions)`** / `noCurrentLocation`
    / `failed(RouteError)`), cancels any in-flight request, and remembers the
    `destination`. **M4.5 manual refresh:** `refreshRoutes(from:)` fetches a
    fresh set from the *current* origin (same remembered destination) into a
    separate `refresh` field (`none` / `recalculating` / `options(RouteOptions)` /
    `noCurrentLocation` / `failed`) so the active route / preview / nav UI is
    undisturbed; `clearRefresh()` dismisses it; a fresh `requestRoutes` cancels
    any pending refresh. **M4.6 automatic reroute:** `autoReroute(from:now:)` —
    triggered by off-route detection — runs through the *same* `refresh` field
    and `refreshTask` (so manual + automatic can never run at once or double up),
    marked via **`@Published refreshWasAutomatic`** so the view adopts the
    recommended route instead of offering the set. `canAutoReroute(now:)` gates
    it: a destination, nothing else refreshing, and the
    `autoRerouteCooldownSeconds` (25) since the last automatic run's completion
    elapsed — the **manual Refresh is never gated by the cooldown**, and always
    wins over an in-flight automatic run. A new destination clears the cooldown.
    Still **no polling / timers**. Derived `isRecalculating` /
    **`isAutomaticallyRecalculating`** expose the loading state *synchronously*
    the instant `autoReroute` starts the request (before the API responds) — the
    composing view binds the "Recalculating…" pill to it, and `refreshWasAutomatic`
    being `@Published` guarantees SwiftUI re-renders on that transition.
  - `MapViewModel.setRoute(_ route: Route?)` — a one-route convenience over
    `setRouteOptions` (see the abstraction section above for the M4.5 selection
    API). `setDestination(_:)` clears the route + options + nav progress.
  - `RouteStatusView` — a small transient `.regularMaterial` pill under the
    search card: spinner + "Finding route…", "Waiting for GPS…", or "Route
    unavailable" + Retry. Nothing while idle or loaded. Hidden entirely once
    navigating.
  - `RouteOptionsPanelView` (M4.5) — a compact horizontal row of route-option
    chips (duration prominent, distance + relative label beneath, the selected
    one accented). Used as the preview selector (tap = select) and, with an
    `onDismiss` ✕, for a mid-navigation refresh result (tap = adopt). Never a
    full-screen list. Presentational.
  - `ManeuverCardView` / `ManeuverCard` / `NavigationDistance` (M4.3) — the
    top-of-map CarPlay-style card (large maneuver arrow, big distance, instruction
    + road, a **Refresh** button (M4.5 — spinner while recalculating) + an "End"
    button) and its presentational model + distance formatter
    ("Now" / "220 m" / "1.4 km"). `StartNavigationButton` — the capsule action
    shown over the route preview. Both presentational; `MapFullScreenView` owns
    their visibility.
- **[Implemented]** `GoogleMapProvider` — the live Google Maps view, and the only
  Map file importing `GoogleMaps`. Wraps `GMSMapView` in a private
  `UIViewRepresentable`; the `Coordinator` owns the one vehicle-indicator
  `GMSMarker` plus keyed dictionaries of route `GMSPolyline`s / destination
  `GMSMarker`s and **diffs each `MapContent`** against the last render (camera /
  vehicle / polylines / markers applied only on change); it is the
  `GMSMapViewDelegate` and translates tap + `idleAt` callbacks (with a
  `willMove(byGesture:)` flag) into `MapEvent`s. `isMyLocationEnabled = false`
  (position comes from the relay, not the iPad's own CoreLocation). The
  `GMSPolyline` sync path (`strokeWidth 6`, `.systemBlue`) draws the **M3 route**.
  **M4.1:** the vehicle `GMSMarker` is `isFlat = true`, centre-anchored, not
  tappable, `zIndex 1`. `vehicleStyle(for:)` — a **pure `nonisolated static`
  helper** (unit-tested, no GMS type) — maps `VehicleIndicator` to
  `.locationDot` / `.directionalPointer(rotationDegrees:)`; `syncVehicle(_:on:)`
  then swaps the marker's icon (code-drawn blue dot vs blue arrowhead) and sets
  `marker.rotation` = the bearing. No `GoogleMapProvider` change was needed for
  M3; M4.1 replaced only the default-red-pin vehicle marker.
  **M4.2 / M4.4:** `applyCamera` handles `.navigation` (`viewingAngle` = pitch;
  the vehicle is anchored at `vehicleVerticalAnchor` of the height by padding the
  top by `(2·anchor − 1)·H` — GMS centres the target in the un-padded region, so
  top padding pushes it *down*); `.follow` / `.fit` reset the padding.
  `idleAt` reports `byUserGesture` from
  `UserGestureLatch` — a pure `nonisolated struct` (unit-tested, no GMS) that
  `willMove(byGesture:)` latches on for any user gesture and `idleAt` consumes.
  The latch is deliberate: a programmatic follow animation can fire *between* a
  gesture starting and the camera settling, reporting `byGesture: false`; that
  must not erase that the user is interacting. **No distance or zoom threshold** —
  any real pan/zoom/rotate, however small, drops follow; a purely programmatic
  move never sets the latch, so there is no feedback loop.
  **M4.3:** no `GoogleMapProvider` change — the dynamic navigation zoom rides in
  on `MapCameraState.zoom` inside the existing `.navigation` plan.
  **M4.4:** the only `.navigation` change is the padding above — the shortened
  route line is still just a `MapPolyline` the `GMSPolyline` sync path draws.
  **M4.5:** `syncPolylines` now styles each `GMSPolyline` by `MapPolyline.role`
  (`.selected` → thick `.systemBlue`, `zIndex 2`; `.alternative` → thinner
  `.systemGray`, `zIndex 1`) in a single `style(_:as:)` helper, keys each by
  `userData` and makes them `isTappable`, and `mapView(_:didTap overlay:)` emits
  `.tappedRoute(id:)`. The destination pin moves to `zIndex 3` and the vehicle
  marker to `zIndex 10`. Route geometry is never duplicated — the provider only
  renders the `MapPolyline`s it is handed.
- **[Implemented]** `GoogleMapsConfiguration` — reads `GoogleMapsAPIKey` from the
  bundle (build-injected, see §9), exposes it as `apiKey`, and calls
  `GMSServices.provideAPIKey`; returns `false` and does nothing if unset. No key
  in source. `GooglePlacesConfiguration.bootstrap()` reuses the same `apiKey` for
  `GMSPlacesClient.provideAPIKey`. Both are called from `DashApp.init()`.
- **[Implemented]** `MapFullScreenView` renders a full-screen `DashMapView` with
  the `MapSearchView` + `RouteStatusView` overlay. It is now `MapFeature`'s
  full-screen experience, opened from the shell's sidebar / Home; the dashboard
  widget presentations at each `ComponentSize` are M5.2.1.
- **[Verified · automated]** `PacketLineBufferTests` (9): single line, two lines
  per chunk, line split across chunks, partial trailing line held, blank lines
  ignored, malformed line skipped, oversized line dropped then recovers, `reset()`,
  round-trip against `LocationWireFormat`.
- **[Verified · automated]** `LocationStoreTests` (10): initial state, ingest
  becomes source of truth, latest-wins, live within interval, goes stale, stale
  retains packet, recovers after stale, watchdog `Task` fires on its own,
  `connectionEnded()` returns to `.waiting` keeping the last packet,
  `connectionEnded()` stays `.waiting` past the interval.
- **[Verified · automated]** `ConnectionCoordinatorTests` (22), driven through a
  stub `LocationReceiving` + a real (suite-isolated) `KnownDeviceStore` — no
  Bonjour/TCP:
  - state machine: starts disconnected; `disconnected→discovering` on
    `startSession()`; `discovering→connecting→connected` (exposes
    `connectedRelayID` / `connectedDisplayName`); `connected→discovering` on a
    transport drop; pure phase mapping; packets flow to `LocationStore` only;
    deliberate disconnect resets the store signal.
  - **first-time pairing:** multiple discovered relays are surfaced and **none is
    auto-chosen**; selecting one targets it **and** persists the `KnownRelay`;
    the pairing survives a fresh `KnownDeviceStore` instance.
  - **subsequent launches:** a paired relay is **targeted immediately** on
    `startSession()`; an **unrelated nearby relay is never targeted**; when the
    paired relay is not visible the coordinator keeps looking and exposes its
    name, offering no stranger.
  - **Disconnect vs Forget:** Disconnect keeps the `KnownRelay`; **a deliberate
    disconnect does not immediately reconnect** even when the paired relay is
    re-discovered; the user can `startSession()` again afterwards; **Forget**
    removes the `KnownRelay`, clears the target, and returns to first-time
    browsing.
  - **friendly name at pairing:** `pairAndConnect(to:named:)` stores the trimmed
    user-typed name as `KnownRelay.displayName` (**stable `id` unchanged**), a
    blank/whitespace/nil name falls back to the advertised name, and
    `pairedRelayDisplayName` exposes the name even while `.connected` (for
    `ConnectedControlView`).
  - separation: remembering a device doesn't change connection state; connecting
    doesn't auto-pair.
- **[Verified · automated]** `ConnectedControlViewTests` (2): the paired-device
  label uses the friendly name, and falls back to "DashRelay" when it's nil/blank.
- **[Verified · automated]** `KnownDeviceStoreTests` (7): starts empty (no
  `pairedRelay`), remember adds and becomes `pairedRelay`, remember is idempotent
  by id and refreshes the name, forget removes, multiple devices, `forgetAll`,
  persists across store instances.
- **[Verified · automated]** `ConnectionSetupViewTests` (8): the `Model` →
  `Display` mapping — `disconnected` offers *Search*, no spinner; *discovering*
  with candidates and no pairing shows the **device list**; *discovering* while
  paired-but-not-visible shows "**Looking for `<name>`…**" and no list;
  *connecting* / *discovering-empty* show a spinner + **Stop Searching**;
  *connecting* names the paired relay; *connected* offers no action;
  **`forgetLabel` is "Forget `<name>`" exactly when a device is paired** (and
  "Forget This iPhone" for a nameless pairing); every state has status text.
- **[Verified · Xcode Preview]** Earlier `ConnectionSetupView` pairing states
  were rendered via Xcode Previews (device list, "Looking for `<name>`…") in
  portrait and landscape. **This round's changes — the "name this iPhone" alert,
  the "Stop Searching" label, "Forget `<name>`", and `ConnectedControlView` —
  have not been re-rendered on a real screen** (covered by the `Display` /
  `deviceLabel` unit tests). Layout is unchanged (same width-capped
  `GeometryReader` + `ScrollView`); the overlay uses `.overlay(alignment:
  .topTrailing)` + safe-area padding.
- **[Verified · automated]** `MapCameraStateTests` + `MapViewModelTests` (7,
  unchanged): default heading is `nil`, `following` re-centres and keeps zoom,
  negative heading → `nil`, zero heading kept, default provider is `.googleMaps`,
  `update(with:)` moves the camera, `update(with: nil)` is a no-op.
- **[Verified · automated]** `MapContentTests` (18): `MapCoordinateBounds` math;
  `MapViewModel` — starts `.cruising`/following with `.follow(.default)`, a fix
  moves vehicle + follow camera together, `nil` fix is a no-op, zoom persists;
  `setMode` camera plans (preview-no-destination → follow, navigating →
  `.navigation`); **M2**: `setDestination` pin + `.fit` preview, later fix moves
  the vehicle not the camera, clearing resumes `.follow`, nameless → titleless;
  **M4.1**: heading orients / invalid heading clears / follows latest coordinate;
  tap events + programmatic camera-idle are inert.
- **[Verified · automated]** `VehicleIndicatorTests` (9 — M4.1): `LocationPacket`
  → `VehicleIndicator` (coordinate; heading kept for usable / zero, dropped for
  negative / NaN); `GoogleMapProvider.vehicleStyle` dot vs rotated pointer. The
  `GMSMarker` icon drawing / rotation stays device-validated.
- **[Verified · automated]** `CameraFollowTests` (20 — M4.2): **cruising** —
  follow on by default + camera tracks the vehicle, a user pan turns follow off,
  **even a tiny sub-metre / 0.01-zoom user gesture turns follow off**, then a fix
  moves the vehicle not the camera, a programmatic camera-idle never turns follow
  off, `recenter()` re-arms follow + snaps to the vehicle at the user's zoom +
  uses the latest fix, a mode change re-arms follow; **preview** — one-shot fit
  unchanged, a pan does not drop follow / show the button, `recenter()` is a
  no-op; **navigating** — enters + follows with `.navigation`, respects
  follow-off, `recenter()` uses `.navigation`, the plan is tilted + below-centre;
  **`UserGestureLatch`** — starts clear, a gesture latches until `idleAt`
  consumes it, a programmatic move alone never latches, a programmatic move
  interleaved with a gesture does **not** clear the latch, the latch does not
  leak to the next idle. The `GMSMapView` camera / gesture wiring stays
  device-validated.
- **[Verified · automated]** `PlaceSearchTests` (11): `DestinationStore`
  select/clear; `PlaceSearchViewModel` (stub service) — a sub-minimum query
  doesn't hit the service, a valid query publishes suggestions, `origin` is
  forwarded for biasing, a service failure clears results + shows an error, the
  debounced path runs, clearing the query wipes results, `choose` resolves →
  `onDestinationChosen` + field reset, a failed resolve shows an error + hands
  out nothing, `reset` clears. **Google's SDK is not exercised** — a stub stands in.
- **[Verified · automated]** `RouteOptionsTests` (M4.5): empty → `nil`; a single
  route → no alternatives, self selected + recommended; multiple → `[0]`
  recommended + selected, the rest alternatives (order preserved); an explicit
  `selectedID` honoured / unknown falls back to `[0]`; `selecting` changes the
  pick / ignores unknown ids; `summaries` — one per route, formatted, selection
  flagged, and relative labels ("Recommended" / "3 min faster" / "5 min longer" /
  "Similar time").
- **[Verified · automated]** `RouteTests` (M3–M4.5): `Route` / `GooglePolyline`;
  `GoogleRouteService.makeRequest` (POST, endpoint, key + step field mask, DRIVE
  body, **`computeAlternativeRoutes: true` + still `TRAFFIC_UNAWARE`**);
  `parseRoutes` from canned JSON — single route (`"route-0"`), **every
  alternative in order with stable ids**, routes with degenerate geometry
  dropped, empty / degenerate-only / malformed → `.noRoute`; `RouteStep` parse +
  `Maneuver` table + road-name heuristic; `GoogleRouteService` end-to-end with a
  **mocked `URLSession`** (200 → `[Route]`, 403 / transport / no-key →
  `.unavailable`); `RouteViewModel` — loads a `RouteOptions` (recommended
  selected), **single-route fallback**, `noCurrentLocation`, `.failed`, clear,
  cancels-in-flight, and **manual refresh** (uses the current origin + remembered
  destination, keeps `state`, `recalculating` → `options`; no-current-location /
  no-destination / failure land on `refresh` only; `clearRefresh` / a fresh
  request clears it); `MapViewModel` route options — preview draws all
  (`.selected` + `.alternative`), `selectRouteOption` in preview makes one active
  + re-fits + no stale line + does **not** start navigation, a route tap selects
  in preview and is ignored while navigating, Start uses the selected route +
  drops alternatives, single-route fallback, and refresh-during-navigation:
  offering leaves the active route alone, adopting swaps it + resets progress +
  keeps the vehicle indicator + removes the old geometry + respects follow-off.
  **The live Routes API is not called** — canned data / a mock transport stand in.
- **[Verified · automated]** `NavigationTests` (M4.3 + M4.4): `RouteGeometry` —
  haversine / length / point→polyline projection incl. end-clamping, and **M4.4**
  `remainingPolyline` (whole route at the start, starts under the vehicle +
  ends at the destination mid-route, only ever shrinks, `[]` past the end,
  degenerate input returned untouched); `NavigationProgressCalculator` — initial
  maneuver + distance, distance shrinks along a step, one maneuver per fix, **a
  single on-route fix two maneuvers ahead advances only one**, **a fix ~2 km
  off-route is ignored**, monotonic, full-route walk → `isArrived`, step-less
  route benign; `NavigationViewModel` — inactive / start needs route + origin /
  card advances / arrival card / stop; `ManeuverCard` / `NavigationDistance` /
  `ManeuverType`; `MapViewModel` navigation camera — start-gate, the plan tilts +
  **anchors the vehicle a little below centre (0.5 < anchor < 0.7)**, no
  progress → base zoom, nearing a significant turn zooms in and eases back,
  non-significant never zooms, quantised, follow-off freezes it, recenter
  restores, leaving clears progress + zoom; **M4.4 route rendering** — full route
  while previewing (unchanged by later fixes), clipped to the road ahead while
  navigating, shrinks further as the vehicle advances, cleared on arrival and on
  End, and `vm.route.polyline` stays the full geometry throughout;
  **M4.5 `NavigationViewModel.reroute`** — swaps the route + re-seeds progress
  from the current position, keeps the session, and is a no-op when inactive /
  without an origin.
  **No SDK, no live Routes API.**
- **[Verified · automated]** `RouteInfoTests` (M4.4): `RouteFormat` — distance
  bands + km switch, duration to minutes then hours, and that the clock string
  **follows the injected locale** (en_US "3:45 PM" vs en_GB "15:45") **and time
  zone** (NY 15:45 → LA 12:45); `Duration.inSeconds` for whole / fractional
  values; `remainingDuration(along:)` scales by distance fraction, is `.zero` on
  arrival / for a zero-length route, and clamps an overshoot;
  `RouteInfo.preview` / `.remaining` build the right figures and ETA
  (now + duration / now + remaining), the two `Kind`s carry distinct labels;
  **edge cases** — arrival (0 m / "< 1 min" / ETA = now) and a 3 m remaining
  distance ("0 m"); `NavigationViewModel.routeInfo` is `nil` inactive, live once
  navigating, `nil` again after arrival. **Pure — ETA computed from an injected
  `now`, no real clock.**
- **[Verified · automated]** `OffRouteTests` (M4.6, 38): **`OffRouteDetector`** —
  on-route stays quiet, a single noisy fix never triggers, **two consecutive
  meaningful fixes still don't trigger** (the third confirms), < `confirmationFixCount`
  stays "possibly", a run confirms + signals **once**, the hysteresis band never
  confirms, a still-off-route episode **re-signals after `resignalAfterFixes`**,
  rejoining ends the episode and a later deviation can trigger again, `reset()`
  re-arms, a degenerate route polyline is inert; **the refined thresholds**
  (20 / 35 / 3) are asserted explicitly — hysteresis kept, count ≥ 3, a ~25 m
  drift reads "possibly" (not on-route), a ~40 m deviation confirms on the third
  fix; **`RouteViewModel.autoReroute`** — uses the current origin + remembered
  destination, offers the set with `refreshWasAutomatic` while `state` is
  untouched, a failure keeps `state` + arms the cooldown, no destination / no fix
  → no request, **no concurrent auto reroutes**, **refused while a manual refresh
  runs**, a manual refresh **interrupts an in-flight auto reroute** with no stale
  result, the **cooldown blocks a second run until it elapses**, the **manual
  Refresh ignores the cooldown**, a new destination clears it, `clearRefresh`
  resets the flag; **the loading state** — `isAutomaticallyRecalculating` is
  `true` *synchronously* the instant `autoReroute` starts (before the request
  resolves), `objectWillChange` fires so SwiftUI observes it, a manual refresh's
  recalculating state is **not** flagged automatic, a failed auto-reroute drops
  the loading state but keeps `refreshWasAutomatic` for the failure copy,
  `clearRefresh` ends it; **`NavigationViewModel`** — on-route drive never asks,
  one wild fix never asks, a sustained deviation raises `needsAutomaticReroute`
  once and `clearRerouteRequest` clears it, `reroute()` re-arms against the new
  route, `stop()` clears, inactive updates are inert; **adoption** (the exact
  `ContentView` call sequence) — session / mode / destination / vehicle
  preserved, progress re-seeded against the new route, the alternatives retained
  in `MapViewModel.routeOptions` and the old geometry gone. **Pure — no SDK, no
  live Routes API, `now` injected for the cooldown.**
- **[Verified · on device / simulator]** Dash builds (clean, no warnings). Before
  the M1 pass it launched, initialised the Google Maps SDK (v11.1.0), and
  rendered the map + vehicle marker.
- **[Verified · on device]** M2 autocomplete on the physical iPad:
  `GooglePlaceSearchService.suggestions(...)` against the live **Places API (New)**
  returns real origin-biased results (`GMSPlacesClient.provideAPIKey` is working,
  the key is authorised for Places), `mapSuggestion`'s field mapping
  (`attributedPrimaryText` / `attributedSecondaryText` / `attributedFullText` /
  `distanceMeters`) is correct, and `MapSearchView`'s suggestion list renders.
  One styling bug fixed as part of this (secondary line + distance were invisible
  — see the header note and §6). **Still not device-verified:** choosing a
  suggestion → `details(for:)` Place Details resolve → `Destination`, the
  destination pin dropping on the map, and the `.destinationPreview` camera
  framing. The `GoogleMapProvider` delegate/diffing rewrite (M1) is also still
  only unit-covered + clean-build (see §6).
- **[Verified · on device]** **M3 routing** on the physical iPad: selecting a
  destination fires one `computeRoutes` request against the **live Routes API**,
  the route returns, and the **blue polyline draws** on the map with the preview
  camera framing it. Getting there needed the `X-Ios-Bundle-Identifier` header
  (the key's iOS application restriction was blocking the REST call with an
  `API_KEY_IOS_APP_BLOCKED` 403 — the Maps / Places SDKs send the bundle id
  automatically, the raw `URLSession` call did not). The Routes API is therefore
  confirmed **enabled and authorised** on the project. Committed in `28b5be5`.
- **[Verified · on device]** **M4.1** current-location indicator on the physical
  iPad: the current location is the blue dot / pointer (not a red pin), it moves
  with each fix, and it reads as distinct from the destination pin + route.
  Committed in `8255749`.
- **[Verified · on device]** **M4.2** camera follow / manual pan-zoom / recenter
  on the physical iPad: cruising follows the vehicle, any-size pan/zoom drops
  follow and shows the `RecenterButton`, GPS fixes move the vehicle under a fixed
  camera while follow is off, and recenter restores it. The initial pass used a
  distance-threshold gesture heuristic that let small/fast gestures slip through;
  it was removed (any `willMove(byGesture:)` gesture drops follow) and the fix
  re-verified. Committed in `d8b291e`.
- **[Verified · on device]** **M4.3** start navigation & maneuver guidance on the
  physical iPad: the **Start Navigation** button appears over a loaded route
  preview; tapping it enters `.navigating` and shows the **maneuver card**; the
  card's arrow / instruction / distance update as the position changes along the
  route; the navigation camera follows with the tilt + below-centre framing;
  **dynamic maneuver zoom** tightens approaching a turn and eases back after; a
  manual pan/zoom still drops follow and recenter restores navigation follow; the
  route line + vehicle indicator stay correct. Builds clean (app + device), +37
  unit tests. Committed `a262a9c`.
- **[Verified · on device]** **M4.4** route info & ETA (+ the camera / route-clip
  / layout polish pass) on the physical iPad. Committed `4697557`.
- **[Verified · on device]** **M4.5** multiple route options + manual route
  refresh. Committed `678e478`. +27 unit tests cover the selection / refresh /
  render state.
- **[Not yet verified on device]** **M4.6** smart off-route detection +
  automatic rerouting. Committed `73879e7`. On a real drive, still to confirm: the
  detector's thresholds behave on a genuine missed turn (confirm within a few
  fixes, no false trigger on a bad-GPS stretch); the automatic `computeRoutes`
  reroute fires; the recommended route is adopted mid-drive without restarting
  the session (progress / follow camera / maneuver card / ETA stay correct); the
  "Recalculating…" pill shows without covering the map; a failed reroute leaves
  the current route intact; the 25 s cooldown and the manual-Refresh interaction
  hold up. Builds clean (app), +38 unit tests, not yet installed / driven.
  *(2026-09-03 refinement folded in: thresholds tightened to 20 / 35 / 3, and the
  "Recalculating…" pill now bound to a synchronously-set `@Published` state so it
  is visible for the whole request — both covered by new unit tests, still to see
  on a real drive.)*

### CarPlay-style dashboard shell (M5.0 – M5.2.0)

- **[Implemented · device-verified]** **M5.0 — shell / feature seam.** Committed
  `258ffde`. `DashFeature` protocol + `FeatureManifest` + `FeatureRegistry`
  (`makeDefault()` = the one place features are declared) + `ComponentSize`;
  `ShellSurface` / `ShellStore` (pure navigation state — `home(page)` /
  `dashboard(page)` / `app(FeatureID)`, `openApp`/`closeApp` returning to the
  prior surface); `DashboardShell` (the single layout owner) with a persistent
  `SidebarView` (Home / Dashboard / one button per feature; `ConnectedControlView`
  moved here from the old `RootView` overlay), a placeholder `HomePlaceholderView`
  launcher, and a placeholder dashboard. `RootView` now shows `DashboardShell`
  (not the map) when connected. `MapFeature` wraps the existing full-screen Map.
  +23 unit tests.
- **[Implemented · device-verified]** **M5.1 — app-scoped Map state.** Committed
  `e8e913f`. The five Map view models (`MapViewModel` / `DestinationStore` /
  `PlaceSearchViewModel` / `RouteViewModel` / `NavigationViewModel`) moved from
  `@StateObject`s inside the old `ContentView` onto `MapFeature`, which is held
  for the app's lifetime by the `FeatureRegistry`. `ContentView` →
  `MapFullScreenView`, which now only *observes* those instances. Result: leaving
  and returning to Maps (Maps → Home → Maps) no longer resets an active route /
  navigation session. `makeFullScreenView()` returns a cached `AnyView` so shell
  `body` re-renders don't rebuild the map underneath a live session. Routing /
  navigation algorithms unchanged. +6 unit tests (incl. "an active navigation
  session is not recreated by re-presenting Maps").
- **[Implemented · device-verified]** **M5.2.0 — dashboard layout foundation**
  (§5 item 34; **working tree, not yet committed**). `Shell/Dashboard/`:
  - **`DashboardGrid`** — the fixed **6 × 4** cell grid. The *shell* owns the
    `ComponentSize` → footprint mapping: `.compact` = 2 × 1, `.medium` = 3 × 2,
    `.large` = 6 × 2, `.full` = the whole grid (rejected as a widget). `GridPoint`
    / `GridSpan` / `GridRect` (half-open rect + `intersects`); `contains(_:)`.
  - **`DashboardLayout`** — SDK-neutral `Codable`: ordered `[DashboardPage]`, each
    an ordered `[WidgetPlacement]` where a placement is
    `{ id: UUID, featureID: FeatureID, size: ComponentSize, origin: GridPoint }`.
    Placement identity is part of `Equatable` and round-trips through `Codable`.
    `DashboardLayout.starter(featureID:)` builds the seed.
  - **`DashboardLayoutValidator`** — pure. `validate(_:grid:)` (structural:
    duplicate id / non-widget size / out-of-bounds / per-page overlap) and
    `@MainActor validate(_:grid:registry:)` (adds unknown-feature /
    unsupported-size). Not owned by the store — the store only *uses* the
    structural check as a load-time sanity gate.
  - **`DashboardLayoutStore`** — `@MainActor ObservableObject`. Persists a
    private `{ version: Int, layout: DashboardLayout }` JSON envelope under
    **`shell.dashboardLayout.v1`** in `UserDefaults`. `init` loads it only if it
    exists, decodes, `version == schemaVersion` (**1**), *and* passes the
    structural validator — otherwise the injected **seed**. `replace(with:)` /
    `resetToDefault()` are the save path (no editing UI calls them in M5.2.0).
    First run persists nothing, so a future default still takes effect.
  - **`DashboardSpaceView`** — replaces `DashboardPlaceholderView`. Reads the
    store, resolves each placement's `featureID` through `FeatureRegistry`, calls
    `DashFeature.makeComponentView(size:)` (a labelled placeholder for Maps until
    M5.2.1), absolute-positions each widget on the grid from a `GeometryReader`,
    and shows simple prev/next + page dots when there is more than one page.
    Unknown feature / unsupported size / `.full` → a labelled `UnresolvedWidgetView`.
  - **Default layout** (`DashApp` seeds it with
    `DashboardLayout.starter(featureID: MapFeature.id)`): **two pages, Maps only**
    — page 1: `.large` at (0,0) + `.medium` at (0,2) + `.compact` at (3,2);
    page 2: `.large` at (0,0) + `.medium` at (0,2). Demonstrates multiple sizes,
    positions, and pages without inventing fake features. Validated clean against
    the real registry by a test.
  - **Boundaries held.** `DashboardShell` gains only `@EnvironmentObject
    layoutStore` + a `DashboardGrid` constant + the `.dashboard(page:)` →
    `DashboardSpaceView` wiring; it still references no Map view model. The store
    holds no runtime feature state. `MapFeature` is unchanged (no grid dimensions
    leak into it).
  - **Not in M5.2.0:** real Map component rendering, editing / drag / resize,
    Speedometer, Music, `ThemeManager`, wallpapers, battery/network status. No
    change to routing / navigation or full-screen Maps.
  - +24 unit tests (`DashboardLayoutTests` 16, `DashboardLayoutStoreTests` 8).
    Full suite **347/347**, build clean. **Physically verified on the iPad** —
    the dashboard page renders the placeholder widgets on the grid and page
    navigation works.

### End-to-end

- **[Verified · on device]** Real iPhone → iPad location transfer has been
  confirmed working on physical hardware by the developer: DashRelay on the phone
  is discovered over Bonjour, the iPad connects, and relayed GPS packets reach
  `LocationStore`. This was a manual on-device check; there is no automated
  end-to-end / two-device test in the repo, so it cannot be re-verified from a
  clean checkout alone.
- **[Verified · simulator + real relay]** During the connection/session-layer
  work, the Dash app running in the simulator discovered a real DashRelay
  advertising `_dashrelay._tcp` on the LAN, completed
  `discovering → connecting → connected`, and `RootView` switched from the
  not-connected screen to the dashboard — exercising the new gate end to end.
  (Deliberate disconnect and re-connect are covered by unit tests, not this
  manual check.)
- **[Verified · on device, partial]** The **pairing flow was physically tested**
  iPhone↔iPad over the iPhone's Personal Hotspot. First-time discovery + pick +
  connect works. Getting there needed a fix: `NWBrowser` was created with the
  PTR-only `.bonjour(type:domain:)` descriptor, so every `NWBrowser.Result`
  arrived with `metadata == .none` and the identity TXT record never reached
  Dash — the browser now uses **`.bonjourWithTXTRecord(type:domain:)`**
  (`LocationReceiver`; `LocationReceiverTests` covers the metadata → advertisement
  parse incl. the nil-metadata case). The `[DISCOVERY-DIAG]` `os.Logger` lines
  used while debugging this on hardware were removed before commit — **no
  diagnostic logging is in the source.**
- **[NOT verified on hardware]** Still only automated-verified: auto-preferring
  the paired relay on a *later* launch, "Looking for `<name>`…" when it's absent,
  Disconnect, Forget, "Stop Searching", DashRelay "Stop Sharing", the "name this
  iPhone" prompt, and `ConnectedControlView`. Two physical relays being
  disambiguated is also unverified.

### Automated test totals (all passing, 2026-09-03)

| Suite | Tests | Runner |
|---|---:|---|
| `DashSharedTests` | 8 | `swift test` |
| `DashRelayTests` | 32 | `xcodebuild ... -scheme DashRelay` (iOS Simulator) |
| `DashTests` | 344 (per `xcresulttool`; incl. 1 no-op scaffold; +29 M3, +12 M4.1, +20 M4.2, +37 M4.3, +29 M4.4, +27 M4.5, +38 M4.6, +23 M5.0, +6 M5.1, +24 M5.2.0) | `xcodebuild ... -scheme Dash` (iOS Simulator) |
| `DashUITests` | 3 (Xcode scaffold: launch + launch-performance) | `xcodebuild ... -scheme Dash` (iOS Simulator) |

Last full run (`xcodebuild test -scheme Dash`, iPad iOS 26.5 simulator,
2026-09-03, with **M5.2.0 in the working tree**): all pass — **347/347**
reported by `xcresulttool` (344 `DashTests` + 3 `DashUITests`), 0 failures;
build clean (app) with no source warnings. (`-only-testing:DashTests` alone:
**344/344**.)

`DashSharedTests` breakdown: `LocationPacketTests` (4), `RelayAdvertisementTests` (4).
`DashRelayTests` breakdown: `LocationTrackerTests` (7), `LocationBroadcasterTests`
(7), `RelayIdentityTests` (4), `RelaySessionControllerTests` (8),
`RelayStatusViewTests` (6).
`DashTests` (connection/pairing-relevant): `ConnectionCoordinatorTests` (22),
`ConnectionSetupViewTests` (8), `ConnectedControlViewTests` (2),
`KnownDeviceStoreTests` (7), `LocationReceiverTests` (7).
`DashTests` (map): `MapCameraStateTests` + `MapViewModelTests` in
`MapCameraStateTests.swift`; `MapCoordinateBoundsTests` + `MapViewModelContentTests`
in `MapContentTests.swift`; `GooglePlaceSuggestionMappingTests` +
`DestinationStoreTests` + `PlaceSearchViewModelTests` in `PlaceSearchTests.swift`;
`RouteModelTests` + `GooglePolylineTests` + `GoogleRouteServiceMappingTests`
(M3 + M4.3 steps + M4.5 alternatives) + `GoogleRouteServiceTests` +
`RouteViewModelTests` (+ M4.5 refresh) + `MapViewModelRouteTests` +
`MapViewModelRouteOptionsTests` (M4.5) in `RouteTests.swift`;
`RouteOptionsTests.swift` (M4.5 `RouteOptions` model); `VehicleIndicatorTests` +
`GoogleMapVehicleStyleTests` (M4.1) in `VehicleIndicatorTests.swift`;
`CruisingFollowTests` + `PreviewUnchangedTests` + `NavigatingCameraTests` +
`UserGestureLatchTests` (20 total, M4.2) in `CameraFollowTests.swift`;
`RouteGeometryTests` (+ M4.4 `remainingPolyline`) + `NavigationProgressTests` +
`NavigationViewModelTests` + `ManeuverCardModelTests` + `NavigationCameraTests` +
`RemainingRouteRenderTests` (M4.4 route clipping) in `NavigationTests.swift`;
`RouteFormatTests` + `DurationInSecondsTests` + `RemainingDurationTests` +
`RouteInfoTests` + `NavigationRouteInfoTests` (M4.4) in `RouteInfoTests.swift`;
`OffRouteDetectorTests` + `RouteViewModelAutoRerouteTests` +
`NavigationViewModelOffRouteTests` + `AutomaticRerouteAdoptionTests` (M4.6) in
`OffRouteTests.swift`.
`DashTests` (dashboard shell, M5.0–M5.2.0): `ComponentSizeTests` (3);
`ShellSurfaceTests` + `ShellStoreTests` in `ShellStoreTests.swift`;
`FeatureRegistryTests` in `FeatureRegistryTests.swift`; `MapFeatureTests`
(M5.0/M5.1 ownership) in `MapFeatureTests.swift`; `DashboardLayoutModelTests` +
`DashboardGridTests` + `DashboardLayoutValidatorStructuralTests` +
`DashboardLayoutValidatorRegistryTests` in `DashboardLayoutTests.swift`;
`DashboardLayoutStoreTests` + `DashboardSpaceViewTests` in
`DashboardLayoutStoreTests.swift`. (No SwiftUI-render tests — `DashboardShell` /
`SidebarView` / widget rendering stay device/visual-validated;
`DashboardLayout` / `DashboardGrid` / `DashboardLayoutValidator` /
`ShellStore` are pure and fully unit-covered.)
(Map / search / routing have no SDK-level tests — `GoogleMapProvider` /
`GMSMapView` (incl. the M4.1 vehicle-marker drawing and the M4.2 `.navigation`
camera / gesture wiring), `GooglePlaceSearchService` / `GMSPlacesClient`, and the
live Routes API stay device-validated. `GoogleRouteService` is unit-tested with a
mocked `URLSession`; `GoogleMapProvider.vehicleStyle` / `.UserGestureLatch`, the
`RouteGeometry` / `NavigationProgressCalculator` engine, and
`MapViewModel.navigationZoom` are pure helpers unit-tested with no GMS type.)

---

## 4. Current device / testing setup

- **Physical dashboard test device:** iPad (7th generation) — reported by the
  developer as the mounted target device.
- **Companion device:** the developer's iPhone running DashRelay.
- **Orientation:** the iPad's primary intended orientation is **landscape**;
  portrait must remain supported. *Not yet enforced in project config* — both
  Info.plist targets currently allow all four iPad orientations. The map already
  works in either orientation (SwiftUI handles rotation; `GMSMapView` resizes).
- **Automated tests:** Swift Testing (`import Testing`), run on the **iOS
  Simulator** (used "iPhone 17 Pro" during development). `DashUITests` /
  `DashRelayUITests` are Xcode scaffolds only — no real UI tests.
- **Simulator smoke test:** the Dash app has been installed and launched on the
  simulator to confirm the Google Maps SDK initialises and renders; (with a real
  DashRelay on the LAN) that the connection gate reaches `.connected` and shows
  the dashboard; and (without a relay) that `ConnectionSetupView` renders in the
  `discovering` state on iPad portrait + landscape and iPhone portrait. The
  DashRelay app has been launched on the iPhone simulator to confirm
  `RelayStatusView` renders the `waiting` state in portrait and landscape.
- **Xcode project:** single `Dash.xcodeproj`, project object version 77
  (file-system-synchronized groups). `DashShared` is a local SPM package
  referenced by the project.
- **Build settings of note:**
  - App targets `Dash` and `DashRelay`: `IPHONEOS_DEPLOYMENT_TARGET = 18.6`,
    `SWIFT_VERSION = 5.0`, `TARGETED_DEVICE_FAMILY = 1,2` (iPhone + iPad),
    `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  - Test bundles: `IPHONEOS_DEPLOYMENT_TARGET = 26.5`.
  - `DEVELOPMENT_TEAM = LGQX79QMNJ`, automatic signing.
  - Bundle IDs: `com.sakshamsharma.Dash`, `com.sakshamsharma.DashRelay`.
  - `DashShared` package: swift-tools 6.3, Swift 6 language mode.
- **Google Maps SDK:** `github.com/googlemaps/ios-maps-sdk`, up-to-next-major from
  **11.1.0** (`Package.resolved` @ 11.1.0), linked to the **Dash target only**
  (product `GoogleMaps`).
- **Google Places SDK:** `github.com/googlemaps/ios-places-sdk`, up-to-next-major
  from **11.1.0** (`Package.resolved` @ 11.1.0), linked to the **Dash target
  only** (product `GooglePlaces` — the GA Obj-C/Swift-interop SDK, **not** the
  preview `GooglePlacesSwift`). Separate package from the Maps SDK; no shared
  binary, no conflict. iOS 16 minimum (below the app's 18.6 target).

---

## 5. Important architectural / product decisions made since the original spec

1. **Shared wire contract widened beyond `LocationPacket`.** The spec only calls
   for `LocationPacket` in the shared package. We added `LocationWireFormat` to
   `DashShared` as well — the Bonjour service-type string, the ISO-8601
   `JSONEncoder`/`JSONDecoder` configuration, and the `\n` line delimiter — so the
   framing (not just the model) has one definition. `LocationBroadcaster` and
   `LocationReceiver` both route through it.

2. **Newline-delimited JSON over a raw TCP stream** was chosen as the concrete
   wire format (the spec says "sends JSON" without specifying framing). One
   compact JSON object per line, `\n` terminated. `PacketLineBuffer` owns
   reassembly on the receive side.

3. **`LocationTracker` sends raw `CLLocation` values.** Speed stays in m/s and
   heading is `CLLocation.course`, both keeping the negative-means-invalid
   convention. Unit conversion and smoothing are deliberately left to the iPad
   consumers (spec §7), so the relay never massages data.

4. **`LocationStore` watchdog implemented as a cancellable `Task`** (re-armed on
   every packet) rather than a `Timer`, with a pure `refreshSignal(now:)` for
   testability. Default `staleInterval` = 7 s. On staleness the last packet is
   **retained** (last-known position) and only a flag flips.

5. **Multi-instance Bonjour picker — ~~deferred~~ done (superseded by 19–22).**
   Originally `LocationReceiver` connected to the first discovered endpoint. As of
   the pairing work it browses continuously, reports **all** visible relays
   (`onDiscoveryChange`), and connects only to the one the user picked / the
   paired one (`setTargetRelay(id:)`). `ConnectionSetupView` shows the list for a
   first-time pick. Choosing *among several known devices* is still future work
   (`pairedRelay` = the first).

6. **Map abstraction shape. _(widened by item 24, 2026-09-01.)_** `MapProvider`
   is `@MainActor` and returns a type-erased `AnyView` so providers can be held as
   `any MapProvider` and swapped at runtime from a future Settings toggle. The
   original signature was `makeMapView(camera:) -> AnyView`; it is now
   `makeMapView(content: MapContent, onEvent:) -> AnyView`. The spec's `search` /
   `route` / `draw` are still deliberately **not** on this protocol — item 24
   records that they become their own service abstractions instead.

7. **`MapCameraState` is a bespoke SDK-neutral value type** (plain `Double`s, no
   `CLLocationCoordinate2D`) rather than the spec's `CLLocationCoordinate2D`
   signature, to keep the boundary trivially testable and import-free. Item 24
   extends the same principle to `MapCoordinate` / `MapContent` / `MapEvent`.

8. **API key delivery via xcconfig → Info.plist → runtime lookup** (see §9). The
   spec says "supply the key securely"; the concrete mechanism is a git-ignored
   `.xcconfig` feeding `$(GOOGLE_MAPS_API_KEY)` into the Info.plist, read back by
   `GoogleMapsConfiguration`. Nothing hardcoded.

9. **App deployment target lowered to iOS 18.6** for both apps (the initial
   scaffold was created against a newer SDK). Test bundles still sit at 26.5.

10. **Single Xcode project, not a workspace.** `CLAUDE.md` flagged this as an
    open choice; the shared package is wired in as a local SPM reference from the
    one `Dash.xcodeproj` and that has been sufficient so far.

11. **`ContentView` temporarily showed the full-screen map** so the Google Maps
    integration could be exercised end to end. *Superseded by the M5 shell* — the
    full-screen map is now `MapFullScreenView`, opened from `DashboardShell`
    (§5 items 33–34).

12. **Connection/session as a layer above networking + location.** New
    `ConnectionCoordinator` (iPad) and `RelaySessionController` (iPhone) own the
    *lifecycle* of the existing `LocationReceiver` / `LocationBroadcaster` /
    `LocationTracker`. Those types kept their responsibilities (discovery/receive,
    advertise/send, GPS acquisition); the session layer only decides when they
    run and exposes a stable state. `LocationStore` was narrowed to "received
    location data + watchdog" and lost its `linkPhase` (connection state was
    being tracked in two places).

13. **Deliberate disconnect is a first-class, sticky state.** Distinct from an
    incidental drop: it stops the transport *and* GPS and does not auto-reconnect.
    `LocationReceiver`'s existing reconnect loop is left intact for incidental
    drops but is inert after a deliberate `stop()`. `LocationTracker` gained a
    `wantsTracking` gate so an authorization callback can't restart GPS behind
    the session's back.

14. **The relay session gates GPS from `start()` to `stop()`** (not "only while a
    dashboard is connected"). Rationale: background-location reliability (no
    `CLLocationManager` start/stop churn on brief link blips), the spec's emphasis
    on continuous relaying, and the phone being on a charger. The
    `waiting`/`connected` distinction is still exposed (from `clientCount`) for a
    future status UI. Alternative — track only while connected — remains easy to
    switch to in `RelaySessionController`.

15. **Pairing = known-device storage now, pairing *flow* later.**
    **Superseded by 19–22 (2026-09-01).** The pairing flow now exists.
    `KnownDeviceStore` stays persistence-only, but `ConnectionCoordinator` now
    holds an injected `any KnownDeviceStoring` reference (the two are no longer
    "deliberately decoupled") — it reads the store to prefer the paired relay and
    writes to it on an explicit pair/forget. `KnownRelay` is keyed by the relay's
    stable id, not the Bonjour service name. The old
    `ConnectionCoordinator.connectedDeviceName` bridge is replaced by
    `connectedRelayID` / `connectedDisplayName` + the `pairAndConnect` / `forget`
    methods.

16. **`ConnectionState` is its own enum**, not a re-export of
    `LocationReceiver.Status.Phase`. The transport phase is a networking detail;
    the rest of the app depends on the stable `disconnected / discovering /
    connecting / connected` vocabulary the spec's requirements used.

17. **The connection/setup screen is presentational.** `ConnectionSetupView`
    takes a `ConnectionSetupView.Model` (state + `offerableRelays` +
    `pairedRelayName`) + action closures rather than reading `ConnectionCoordinator`
    or `KnownDeviceStore` from the environment. `RootView` is the container that
    reads the single source and wires the actions (including `onSelectRelay` /
    `onForget`). This keeps connection state un-duplicated and the screen
    testable in any state (`ConnectionSetupView.Display`). The dashboard still
    falls back to the setup screen on *any* non-connected state, including a
    brief incidental drop — the "signal lost overlay, keep the dashboard up"
    refinement (spec §3.7 / §4) is still not done here.

18. **DashRelay's status screen follows the same presentational pattern.**
    `RelayStatusScreen` (container, reads `RelaySessionController`) →
    `RelayStatusView` (presentational, `RelaySessionController.State` + closures) →
    `RelayStatusView.Display` (pure `State` → screen mapping, unit-tested).
    Disconnect is wired straight to the existing `RelaySessionController.stop()` —
    no networking/GPS logic in the view. The **connected screen shows a generic
    message and no device name**: the relay only knows an inbound `clientCount`
    (`LocationBroadcaster.Status`), not a Bonjour name for the Dash client — so
    surfacing the connected device would need new plumbing in the broadcaster /
    session layer, deferred with pairing.

19. **Device identity for pairing = a persisted UUID in the Bonjour TXT record.**
    *Decision recorded per the task's "PAIRING IDENTITY" requirement.*
    - **What already existed:** the Bonjour service *type* (`_dashrelay._tcp`,
      shared, not an identity) and the service *instance name* — which
      `LocationBroadcaster` hardcoded to `"DashRelay"` for every relay. So there
      was **no** stable, unique per-device identity: two relays could not be told
      apart, and iOS renames colliding instance names non-deterministically.
      `KnownRelay` keyed on that hardcoded string was unusable for the goals.
    - **Smallest clean change made:** DashRelay mints a random `UUID` once
      (`RelayIdentity`, persisted in `UserDefaults`) and publishes it — plus the
      device name — in the **Bonjour TXT record** via `RelayAdvertisement` (new,
      in `DashShared`, keys `rid` / `name`). Dash reads the TXT record straight
      from `NWBrowser` results (no connection needed) and pairs on the `rid`.
    - **Why the TXT record, not the instance name:** identity, display name, and
      the transient Bonjour name stay separate concerns; a UUID never leaks into
      a user-facing service name; the friendly name can change (phone renamed)
      without breaking the pairing.
    - **Trade-off:** deleting and reinstalling DashRelay generates a new id, so
      the user re-pairs once. Acceptable — it keeps identity purely local, no
      account or server (per the task constraint).

20. **First-time pairing = discover-then-pick; no auto-connect to a stranger.**
    With nothing paired, `LocationReceiver` browses but never connects on its
    own. `ConnectionSetupView` lists every visible relay; the user taps one and
    `ConnectionCoordinator.pairAndConnect(to:)` both persists the `KnownRelay`
    and targets it. A single visible relay is **still** presented as a one-item
    list rather than auto-connected — pairing is always an explicit choice.

21. **Subsequent launches prefer the paired relay, and only it.** `startSession()`
    targets the paired relay's id immediately. `LocationReceiver` connects when
    that id appears and, after an incidental drop, reconnects **only to that id**.
    If it never appears, the screen says "Looking for `<name>`…" indefinitely and
    never offers a nearby stranger. Auto-connect among *known* devices fires only
    when exactly one known relay is visible.

22. **Disconnect vs Forget are distinct, and Forget is a coordinator capability.**
    `disconnect()` ends the session, stays sticky (no auto-reconnect), and keeps
    the `KnownRelay`. `forgetPairedRelay()` removes the `KnownRelay`, clears the
    transport target (dropping the live session if it was to that relay), and
    returns to first-time browsing. The UI exposes Forget as a single small
    "Forget this iPhone" button (no settings screen yet); the model/coordinator
    capability is the durable part.

23. **Connection UX refinement (2026-09-01, post first physical pairing test).**
    Small changes, no architecture change:
    - **Wording** — while not connected, the stop action is **"Stop Searching"**
      (was "Disconnect"); it still calls `disconnect()` (deliberate/sticky). The
      first-time list header is "Choose your iPhone…".
    - **Disconnect from Dash while connected** — a new presentational
      `ConnectedControlView`. Introduced as a `RootView` overlay on the map;
      **M5.0 moved it into the shell sidebar** (`DashboardShell` wires its
      closures to `ConnectionCoordinator`). It offers **Disconnect** (keeps
      pairing) and **Forget `<name>`** via a confirmation dialog. Extends §5
      decision 17 (both connection views presentational; the container wires
      them) to the connected state.
    - **DashRelay stop-while-waiting** — `RelayStatusView`'s `.waiting` state
      gained a **"Stop Sharing"** button (was action-less); it and "Disconnect"
      both call `RelaySessionController.stop()`. So the relay is never forced to
      advertise indefinitely.
    - **Friendly name at pairing** — `pairAndConnect(to:named:)` takes the name
      the user types in a "Name this iPhone" alert and stores it as
      `KnownRelay.displayName`. **The stable `id` (TXT `rid`) is never affected**
      — this is display metadata only (per §5 decision 19, identity ≠ display
      name). Blank/whitespace/omitted falls back to the advertised name.
      `ConnectionCoordinator.pairedRelayDisplayName` surfaces it regardless of
      connection state. There is **no in-place rename** yet — changing the name
      means Forget + re-pair.

24. **Map "M1": widen the rendering boundary before leaning on it (2026-09-01).**
    Purely an architecture pass on `Features/Map/` — **no new SDKs/APIs, no
    search, no routing, no navigation, no Apple Maps, no dashboard/connection
    changes.** Existing behaviour (vehicle marker, follow camera, `LocationPacket`
    → `MapCameraState`, Google rendering) is unchanged.
    - **`MapProvider` stays rendering-only and does not grow feature methods.**
      It went from `makeMapView(camera:)` to `makeMapView(content: MapContent,
      onEvent: @escaping (MapEvent) -> Void)` — one value in, one event closure
      out. Search / autocomplete / place-details / route computation are recorded
      here as **future separate service abstractions** (their own protocols +
      Google/Apple impls), so a MapKit provider is never forced to reimplement
      Google's Places/Routes stack and `MapProvider` never becomes a catch-all.
    - **Small composable SDK-neutral types**, one concern each: `MapCoordinate` /
      `MapCoordinateBounds` (`MapGeometry`), `MapCameraPlan` (`.follow` / `.fit`),
      `MapContent` (camera + vehicle + `polylines` + `markers`), `MapPolyline` /
      `MapMarker` (`MapOverlay`), `MapEvent` + `MapPOI` + `MapCameraPosition`
      (`MapEvent`), `MapMode` (`cruising` / `destinationPreview` / `navigating`).
      `DashMapView` / `MapViewModel` were **not** turned into catch-alls.
    - **`vehicle` is separate from `camera`** in `MapContent` so navigation can
      later offset the camera ahead of the car; today they coincide in `cruising`.
    - **Overlay lists and non-`cruising` modes are modelled but inert** — nothing
      produces routes or destinations yet, so `polylines` / `markers` stay empty
      and `destinationPreview` / `navigating` fall back to `.follow`. The
      `.fit(bounds:padding:)` camera plan and `MapCoordinateBounds([…])` exist for
      route-preview framing but are unused.
    - **`GoogleMapProvider` now owns a `GMSMapViewDelegate` + `MapContent`
      diffing.** The `Coordinator` keeps keyed `GMSPolyline` / `GMSMarker`
      dictionaries and applies only what changed between renders; delegate
      callbacks (tap-at, tap-POI, tap-marker, `idleAt` + `willMove(byGesture:)`)
      become `MapEvent`s. `MapViewModel.handle(_:)` is a **documented no-op seam**
      for now.
    - Incidentally fixed the two pre-existing `MapViewModel` main-actor-isolation
      build warnings (the `camera: MapCameraState = .default` default args are
      gone; the neutral value types are `nonisolated`).

25. **Map "M2": destination search via a service abstraction, not the renderer
    (2026-09-01).** Adds Google place search while keeping the search UI ours.
    Scope held to search + destination selection — **no routing, no navigation,
    no Apple Maps.**
    - **`PlaceSearchService` is a separate protocol from `MapProvider`** (per
      item 24's stated plan). Search / autocomplete / place details are not a
      rendering concern and Apple's path (`MKLocalSearchCompleter` /
      `MKLocalSearch`) is unrelated to Google's — so `MapProvider` never grows
      these methods. `GooglePlaceSearchService` is the only new file importing
      `GooglePlaces`; `GooglePlacesConfiguration` (key bootstrap) is the second,
      mirroring the two-file `import GoogleMaps` rule.
    - **Places SDK product choice: `GooglePlaces` (GA), not `GooglePlacesSwift`
      (preview).** Same repo (`ios-places-sdk`), separate SPM package from the
      Maps SDK, no binary conflict. `GMSFetchPlaceRequest`'s `placeProperties`
      imports as `[String]` (the `NS_TYPED_EXTENSIBLE_ENUM` generic doesn't
      bridge), so the service passes `GMSPlaceProperty.<x>.rawValue`.
    - **One API key for both SDKs.** `GooglePlacesConfiguration.bootstrap()` reads
      the same build-injected `GoogleMapsAPIKey` and calls
      `GMSPlacesClient.provideAPIKey`. "Places API (New)" must be enabled on the
      Google Cloud project and allowed by the key's API restrictions — a manual
      console step, not done from code. **This is done and confirmed working on
      device** (§9).
    - **Billing session tokens handled inside the Google impl.** A
      `GMSAutocompleteSessionToken` is minted lazily per search run and dropped
      after `details(for:)`; the neutral protocol has no concept of a session.
    - **Destination state is its own concern.** `DestinationStore` (SDK-neutral
      `@MainActor ObservableObject`) holds the chosen `Destination?`.
      `PlaceSearchViewModel` produces a `Destination` and hands it out via a
      closure — it does not hold the store or the map. `MapViewModel.setDestination(_:)`
      turns a `Destination?` into a `MapMarker` + a `.destinationPreview` /
      `.fit` camera (framing vehicle + destination once; `update(with:)` then
      leaves the camera alone). `ContentView` is the composition point wiring the
      three, none of which reference each other.
    - **`MapMode.destinationPreview` is now realised** (was a fall-back-to-follow
      stub in item 24). `.navigating` still falls back.

26. **Map "M3": routing behind a third service abstraction (2026-09-02).** Given
    the vehicle position + the chosen `Destination`, fetch a driving route and
    draw its geometry. **Routing only — no turn-by-turn, no maneuver instructions,
    no navigation / ahead-of-vehicle camera, no vehicle heading/arrow, no
    automatic rerouting, no voice, no dashboard work.**
    - **`RouteService` is a third protocol, separate from `MapProvider` and
      `PlaceSearchService`** (continuing item 24's plan). It takes plain
      `MapCoordinate`s — not a `Destination`, not a place id — so it stays
      provider-neutral and an Apple `MKDirections` impl slots in later.
    - **`GoogleRouteService` imports no SDK.** The Routes API is REST
      (`routes.googleapis.com`), so it is `URLSession` + `Codable` only. The
      transport and the key accessor are injected, so it is fully unit-tested
      with a mock — no live call in CI. `GoogleMapsConfiguration.apiKey` /
      `.infoPlistKey` were marked `nonisolated` (a plain `Bundle.main` read) so a
      non-main-actor default argument can use it; no behaviour change.
    - **The routing layer owns no GPS.** `RouteViewModel` holds no `LocationStore`
      — `ContentView` passes the latest origin in alongside the destination, the
      same way it already feeds `PlaceSearchViewModel.origin`. No usable origin →
      a distinct `.noCurrentLocation` state, no request sent.
    - **The route renders through the existing overlay channel.** `MapViewModel.
      setRoute(_:)` puts one `MapPolyline` on `MapContent.polylines`;
      `GoogleMapProvider` already turns that into a `GMSPolyline` (built in M1).
    - **The `.destinationPreview` camera fits vehicle + destination + route.**
      `setRoute(_:)` re-derives the `.fit` bounds **once**, when the route loads
      or clears, so the whole route is visible in preview (a wide-bowing route no
      longer runs off-screen). This is a one-shot re-frame — a *later* fix still
      does not move the camera (`update(with:)` leaves it alone in preview), so it
      is not navigation / ahead-of-vehicle camera behaviour, which stays deferred
      to M4. `.cruising` / `.navigating` are untouched — `setRoute` there does
      nothing to the camera.
    - **One route request per destination selection or explicit Retry.** No timer,
      no re-request when a later fix arrives — matches the spec's "call
      Directions/Routes once per trip" cost rule (§9).

27. **Map "M4.1": a navigation-ready current-location indicator (2026-09-02).**
    Replaces the M1 "vehicle" `GMSMarker` (a default red pin — indistinguishable
    from the destination pin) with a proper current-location indicator. **This
    task is the indicator only** — no follow / navigation camera, no recenter, no
    ahead-of-vehicle framing, no dashboard.
    - **`MapContent.vehicle` becomes a `VehicleIndicator`** (coordinate + optional
      heading) rather than a bare `MapCoordinate`. It is deliberately its own
      type, not a `MapMarker`: exactly one per render, and it carries a heading a
      pin never would. `VehicleIndicator.init(_ packet:)` does the heading
      validation (negative / NaN → `nil`), the same rule `MapCameraState.
      following(_:)` already uses — no second copy of the "invalid heading"
      convention, no smoothing.
    - **Heading source is `LocationPacket.heading`** — the relay stream, already
      flowing. No new `CLLocationManager`, no `LocationTracker` /
      `LocationBroadcaster` change, no relay-architecture change.
    - **The dot-vs-pointer decision is a pure `nonisolated static` helper**
      (`GoogleMapProvider.vehicleStyle(for:) -> .locationDot /
      .directionalPointer(rotationDegrees:)`) so it is unit-tested without a
      `GMSMapView`. Only the *drawing* (a code-rendered blue dot / blue
      arrowhead) and `marker.rotation` live in the SDK file and stay
      device-validated.
    - **Camera untouched.** `update(with:)`'s camera line is exactly as M1 left
      it. In `.destinationPreview` (the device-test scenario) the rendered camera
      does not move when the vehicle moves; the pre-existing `.cruising`
      follow-on-fix is unchanged (a genuine follow / recenter feature is M4.2).

28. **Map "M4.2": camera follow, manual pan/zoom & recenter (2026-09-02).**
    Makes vehicle-follow an explicit, toggleable state and adds a recenter
    affordance. **Camera framing only — no turn-by-turn / maneuvers / ETA /
    rerouting / voice / navigation UI / dashboard.**
    - **`MapViewModel.followsVehicle`** (`@Published`, on by default) is the
      provider-neutral follow state. `update(with:)` re-derives the rendered
      camera only in `.cruising` / `.navigating` while it is on; otherwise the
      `VehicleIndicator` moves under a fixed camera. `.destinationPreview` never
      touches the camera on a fix — the M3 one-shot fit is preserved exactly (a
      pan while previewing does not drop follow either).
    - **User gesture vs programmatic.** The distinction is made in
      `GoogleMapProvider`, not the view model, and is driven **solely by GMS's
      `willMove(byGesture:)` flag** — there is no distance/zoom threshold, so
      *any* real pan/zoom/rotate, however small, ends up reported as
      user-driven. A pure `nonisolated struct UserGestureLatch` holds the flag:
      `willMove(byGesture: true)` latches it on, `idleAt` consumes it via
      `consumeOnIdle()`. The latch is deliberate — a programmatic follow
      animation can fire *between* the gesture starting and the camera settling,
      reporting `byGesture: false`; that must not erase that the user is
      interacting. A purely programmatic move never latches, so a follow render
      can never disable itself — no feedback loop. `MapViewModel.handle` turns
      follow off on any user idle and remembers the user's zoom.
      *(Fixed 2026-09-02 after device testing showed the earlier threshold-based
      `isMeaningfulMove` heuristic let small/fast drags and pinch-zooms slip
      through, and a mid-gesture follow animation could clear the state.)*
    - **`recenter()`** re-arms follow and snaps to the vehicle with the current
      mode's plan; `setMode` / `setDestination` also re-arm it. `RecenterButton`
      (a small presentational SwiftUI view, **not** in `GoogleMapProvider`) is
      overlaid by `DashMapView` when `showsRecenterButton` (follow off in a
      follow mode) and wired to `recenter()`.
    - **`MapCameraPlan.navigation(state, pitchDegrees:, focusBelowCentre:)`** —
      the distinct `.navigating` framing: `GoogleMapProvider` sets
      `viewingAngle` = pitch and (as shipped in M4.2) bottom `mapView.padding` =
      viewport-height × `focusBelowCentre`; `state.headingDegrees` becomes the
      camera bearing. `.follow` / `.fit` reset the padding. Constants on
      `MapViewModel` (`navigationPitchDegrees = 55`, then `0.28`).
      *(M4.4 renamed this to `vehicleVerticalAnchor` and switched to top padding —
      the M4.2 version actually pushed the vehicle above centre; see item 30's
      polish pass.)*
    - **`.navigating` has no entry point yet.** Nothing in the M4.2 UI calls
      `setMode(.navigating)`, so the navigation camera is code + tests only until
      the "start navigation" flow lands (M4.3, below).
    - Committed `d8b291e`; device-verified (cruising follow, any-size gesture
      drops follow, recenter).

29. **Map "M4.3": start navigation & maneuver guidance (2026-09-02).** Turns the
    M3 route preview into an active turn-by-turn session with a top maneuver card
    and live progress. **Camera + guidance display only — no off-route detection,
    no rerouting, no alternative routes, no traffic switching, no voice, no lane
    guidance, no dashboard, no Apple provider.**
    - **`Route` gained `steps: [RouteStep]`** rather than a parallel model —
      `RouteStep` is SDK-neutral (`ManeuverType`, instruction, road name,
      maneuver point, step polyline, distance). The drawn overview `polyline` and
      the whole M3 render path are unchanged; `steps` defaults to `[]` so every
      existing caller/fixture still compiles.
    - **Google's maneuver vocabulary stays inside `GoogleRouteService`.** The
      field mask now also requests `routes.legs.steps.*`; new private `Decodable`
      DTOs, the `Maneuver` string → `ManeuverType` table, and the road-name
      text heuristic never leave that file. (These fields move the call to the
      Routes **Advanced** SKU — still free-tier for one user calling once per
      trip; the $1 budget alert in §9 covers it.)
    - **The progress engine is provider-neutral and pure.**
      `NavigationProgressCalculator` (with `RouteGeometry` for the geodesic math)
      turns `LocationStore` position + the active `Route` into the upcoming
      maneuver, distance to it, and remaining distance. It lives in `Routing/`,
      not in `GoogleMapProvider`, and holds no SDK / `LocationStore` / Combine.
      Progress is a single monotone `traveledMeters` scalar; a fix advances the
      displayed maneuver **by at most one** and a fix >~80 m off every step is
      ignored, so GPS noise never skips a turn. `NavigationViewModel`
      (`@MainActor`, mirrors `RouteViewModel`) owns the session lifecycle and
      builds the `ManeuverCard`.
    - **Start Navigation lives in the view model, gated.**
      `MapViewModel.startNavigation()` only fires with a loaded route, a received
      fix, and `.destinationPreview` mode (`canStartNavigation`); `ContentView`
      shows `StartNavigationButton` exactly when that holds. Clearing the
      destination (the card's "End", or the search chip's ✕) stops the session
      and returns to cruising.
    - **Dynamic navigation zoom, kept out of the progress engine.** The
      `.navigating` follow camera keeps M4.2's tilt + below-centre framing but
      overrides the zoom via the pure
      `MapViewModel.navigationZoom(...)` — `navigationBaseZoom` until ~350 m from
      a `warrantsCloserView` maneuver, ramping to `+1.5` by ~40 m, **quantised to
      0.5 steps** so it moves in a few discrete steps rather than nudging every
      fix, easing back to base once the turn is behind. With follow off, progress
      updates never move or zoom the camera; recenter restores navigation follow
      (with the dynamic zoom).
    - **No `GoogleMapProvider` change.** The zoom rides in on
      `MapCameraState.zoom` inside the existing `.navigation` plan.
    - **Physically verified on the iPad** (Start Navigation, maneuver card +
      updates, route progress, navigation follow / recenter, dynamic maneuver
      zoom). Committed `a262a9c`.

30. **Map "M4.4": route info & ETA (2026-09-02).** Adds a bottom route-info
    panel — distance / travel time / ETA — to the route preview, and live
    remaining figures during navigation. **Display only — no new route data, no
    traffic, no rerouting, no dashboard.**
    - **Reuses the existing models.** `RouteInfo` is built from `Route.duration`
      / `Route.distanceMeters` (preview) or `NavigationProgress.distanceRemainingMeters`
      + a new `NavigationProgress.remainingDuration(along:)` (live). There is no
      second route computation and no new field on the wire / DTO.
    - **Remaining duration is proportional, not traffic-aware.**
      `remainingDuration` = `route.duration` × (distance left ÷ total distance).
      Deliberate: it stays consistent with the distance shown and needs no extra
      API call. A real ETA that reacts to traffic is a later task (needs
      `routingPreference: TRAFFIC_AWARE` — a billing change).
    - **Formatting is pure and outside the views.** `RouteFormat` (distance /
      duration / clock) + `Duration.inSeconds` live in `Routing/`, fully
      unit-tested. The ETA **clock string uses `Date.FormatStyle` with the
      viewer's locale + time zone** (both injectable so tests can pin them) —
      no hardcoded "h:mm a".
    - **ETA is computed from `now` at render.** `ContentView` wraps the panel in
      a `TimelineView(.periodic(by: 30))` so a stationary preview ETA still rolls
      over; during navigation it also recomputes on every fix (state change).
    - **Preview vs live are visually + label-distinct** (item 4): the preview
      panel is plain material, "Distance / Time / Arrival"; the live panel is
      blue-accented, "Remaining / Time left / ETA". They never show at once (mode
      switch), and the maneuver card / Start button / camera are untouched.
    - **Physically verified on the iPad** (preview panel, swap to the live panel
      on Start, figures updating as the vehicle moves). Not committed.

    **Polish pass (2026-09-02, also working tree):**
    - **Navigation camera — vehicle below centre.** `MapCameraPlan.navigation`
      now carries `vehicleVerticalAnchor` (fraction of the viewport height from
      the top; `MapViewModel.navigationVehicleAnchor = 0.6`).
      `GoogleMapProvider` pads the top by `(2·anchor − 1)·H` — GMS centres the
      camera target in the region left after padding, so top padding pushes the
      vehicle *down*. The old code used *bottom* padding, which pushed it above
      centre; the pitch / dynamic zoom / follow / recenter / user-pan behaviour
      is otherwise unchanged.
    - **Progressively shortened route line.** A private
      `MapViewModel.refreshRoutePolyline()` (called from `update` / `setMode` /
      `setRoute` / `setDestination`) sets `content.polylines` to
      `RouteGeometry.remainingPolyline(of: route.polyline, from: vehicle)` while
      `.navigating` (the road still ahead), the whole route in preview /
      cruising, and `[]` on arrival / no route. The `Route` model and its
      `polyline` are never mutated — the render geometry is derived each fix from
      the M4.3 projection. `GoogleMapProvider` still just draws the `MapPolyline`
      it is handed.
    - **Preview bottom row.** In `.destinationPreview` the `RouteInfoPanelView`
      and `StartNavigationButton` share one `HStack` (panel `maxWidth: .infinity`
      + larger, button `fixedSize` on the right), capped at 620 pt with the
      existing 16 pt / 28 pt margins — fits portrait and landscape. The live nav
      panel stays on its own row. `RouteInfo` content and Start behaviour are
      unchanged.
    - **Physically verified on the iPad** (camera anchor, route shortening on a
      drive, the preview bottom row in both orientations). Committed `4697557`.

31. **Map "M4.5": multiple route options + manual route refresh (2026-09-02).**
    Google can return alternatives; the driver picks one in the preview or after
    a manual refresh. **No** traffic-aware routing, traffic-coloured polylines,
    polling, off-route detection, automatic rerouting, voice, or dashboard.
    - **`RouteService` returns `[Route]`.** `routes(from:to:)` — `[0]` recommended,
      the rest alternatives, never empty on success. `GoogleRouteService` adds
      `computeAlternativeRoutes: true` (still `TRAFFIC_UNAWARE`), maps every route
      in response order, keys each `"route-<index>"`, and drops unusable ones.
      Google DTOs never leave the file. `Route` gained a stable `id`; nothing
      outside routing interprets it.
    - **Selection is one system, in `MapViewModel`.** `RouteOptions` (routes +
      `selectedID` + `summaries`) is the SDK-neutral model. `RouteViewModel`
      fetches (`state = .loaded(RouteOptions)`); `MapViewModel.setRouteOptions` /
      `selectRouteOption` own which is active and drive the map (`.selected` vs
      `.alternative` `MapPolyline`s, stable ids so switching leaves no stale
      line). `NavigationViewModel` still just tracks progress for the active
      route. No parallel state machine.
    - **Preview selection.** All routes draw; the recommended one is active +
      framed. A tap on a chip (`RouteOptionsPanelView`) or on a polyline
      (`MapEvent.tappedRoute`, preview only) makes that route active and re-fits
      the camera — **navigation is not started**. Start uses the selected route.
      The M4.4 preview bottom row is unchanged; the selector sits above it.
    - **Manual refresh** lives on a separate `RouteViewModel.refresh` field so
      the active route / preview / nav UI is undisturbed while it runs. The
      maneuver-card **Refresh** button calls `refreshRoutes(from: currentOrigin)`
      — **current** location as origin, remembered destination; no fix → a
      `noCurrentLocation` state and no request. On success the new options are
      *offered* (`refresh = .options`) — drawn as alternatives, **the active
      route is not switched**.
    - **Adopting a refreshed route** (tap a chip): `NavigationViewModel.reroute`
      re-seeds progress from the current position, `MapViewModel.selectRouteOption`
      swaps the active `route` + clears `navigationProgress`, the old geometry is
      removed, the vehicle indicator is kept, and **the session is not
      restarted**. The camera only moves if follow is on (`recenter` still
      restores it). Dismissing (✕) keeps the current route.
    - **No automatic switching on time savings.** Alternatives are shown; the
      driver chooses.
    - **Not yet device-verified** — installed on the iPad; selection / refresh /
      render state is unit-tested (+27), the visual + gesture check and one live
      `computeRoutes` alternatives call are pending (§3, §10).

32. **Map "M4.6": smart off-route detection + automatic rerouting (2026-09-02;
    refined 2026-09-03 after a physical drive).**
    Detect when the driver has genuinely left the route and silently fetch a
    fresh one from the current position. **No** traffic-aware routing, traffic
    colours, continuous polling, voice guidance, or dashboard work.
    - **Detection is a pure engine, reusing the M4.3 geometry.**
      `OffRouteDetector` (`Routing/`, no SDK / Combine / async) snaps each fix
      onto `route.polyline` with `RouteGeometry.project` and classifies it
      `onRoute` / `possiblyOffRoute` / `confirmedOffRoute`. **Named conservative
      thresholds** (tightened in the 2026-09-03 refinement from 40 / 70 / 4 —
      the original felt too slow in the car): `onRouteToleranceMeters` (**20**,
      ~1 lane) and `offRouteThresholdMeters` (**35**, ~a road away) with a
      hysteresis band between them, `confirmationFixCount` (**3**) *consecutive
      meaningful* off-route fixes to confirm — one **or two** noisy fixes can
      never trigger — and `resignalAfterFixes` (8) before it re-asks for a
      still-unresolved episode. It signals **once per episode**; rejoining the
      route (≤ tolerance) ends the episode and re-arms.
    - **One navigation/routing state system, not a second.**
      `NavigationViewModel` owns the detector (fed from the existing
      `update(with:)` fix pump), exposes `offRouteStatus` +
      `needsAutomaticReroute`, and re-arms on `start` / `reroute` / `stop`.
      `RouteViewModel.autoReroute(from:)` runs through the **same `refresh` field
      and `refreshTask`** as the M4.5 manual Refresh — so the two can never run
      at once or double up — distinguished only by `refreshWasAutomatic`.
    - **Current location → existing destination.** `autoReroute` uses the latest
      origin `ContentView` already feeds in and the destination `RouteViewModel`
      already remembers. No fix → it returns false silently (the detector
      re-asks); no destination → false.
    - **Cooldown + concurrency.** `canAutoReroute(now:)` refuses a second
      automatic run within `autoRerouteCooldownSeconds` (25) of the previous
      one's *completion* (success or failure), or while any refresh is in
      flight. The **manual Refresh is never gated by the cooldown** and always
      wins over an in-flight automatic run (cancels it). A new destination
      clears the cooldown.
    - **Adopt on success, keep everything on failure.** On a fresh set
      `ContentView.adoptAutomaticReroute` runs `NavigationViewModel.reroute` +
      `MapViewModel.setRouteOptions` + `selectRouteOption(recommended)` +
      `setNavigationProgress` — the recommended route becomes active, progress
      re-seeds against it, and destination / navigation mode / vehicle indicator
      / camera-follow / maneuver guidance / ETA / remaining-route clipping are
      all untouched. The returned **alternatives stay in
      `MapViewModel.routeOptions`** (drawn `.alternative`). On failure the
      handler does nothing — the existing route + session stand.
    - **Lightweight "Recalculating…" state, visible for the whole request
      (2026-09-03 refinement).** `RouteViewModel` exposes derived
      `isRecalculating` / **`isAutomaticallyRecalculating`**, and
      `refreshWasAutomatic` is now `@Published` — so the state flips
      *synchronously* the instant `autoReroute` starts the request (never
      waiting on the API) and SwiftUI re-renders on that transition. The pill is
      a small material capsule under the maneuver card with a snap-in transition
      (a fast Routes response can't leave it mid-fade); it never covers the map
      and the current guidance stays on screen. A failed automatic reroute
      swaps it for a dismissible "Couldn't recalculate — keeping current route"
      pill.
    - **Google stays isolated.** No `RouteService` / `GoogleRouteService` change
      — `autoReroute` reuses `RouteService.routes(from:to:)`.
    - **Not yet device-verified** — off-route classification (incl. the refined
      thresholds), auto-reroute, adoption, and the loading-state transition are
      unit-tested (+38); a live drive that misses a turn is pending (§3, §10).

33. **Dashboard shell / feature seam (M5.0 + M5.1).**
    The CarPlay-style presentation layer is a **standalone layer that owns
    layout and navigation** and knows nothing about any feature's internals
    (spec §8). It replaces the old `RootView → ContentView` full-screen-map
    shell.
    - **`DashFeature` is the only contract.** A feature exposes a
      `FeatureManifest` (id, title, symbol, supported `ComponentSize`s, default
      size), `makeFullScreenView() -> AnyView`, and
      `makeComponentView(size:) -> AnyView`. Nothing else. `FeatureID` is a
      stable `String`; **adding a feature is a new `DashFeature` type + one line
      in `FeatureRegistry.makeDefault()`** — no shell change. Features never
      reference `Shell/`; the shell never references a Map view model.
    - **`ShellStore` is pure navigation state.** `ShellSurface` is
      `home(page)` / `dashboard(page)` / `app(FeatureID)` (`Codable`).
      `openApp` remembers the current space; `closeApp` returns to it;
      navigating to a space also leaves an open app. No feature-specific logic,
      no SDK types.
    - **`DashboardShell` is the single layout owner.** Persistent `SidebarView`
      (Home / Dashboard / one button per registered feature) + a content area
      switching on `ShellSurface`. `ConnectedControlView` (Disconnect / Forget)
      moved into the sidebar from the old `RootView` overlay — behaviour
      unchanged. `RootView` shows `DashboardShell` (not the map) while connected;
      the connection gate + `ConnectionSetupView` are untouched.
    - **Map runtime state is app-scoped (M5.1).** `MapFeature` — the *only*
      bridge between `Shell/` and Map code — now owns `MapViewModel` /
      `DestinationStore` / `PlaceSearchViewModel` / `RouteViewModel` /
      `NavigationViewModel` for the life of the app (they were `@StateObject`s
      inside the old `ContentView`). `ContentView` became `MapFullScreenView`,
      which only *observes* them. So **Maps → Home → Maps no longer resets an
      active route / navigation session.** The view-model wiring (the
      `LocationStore` fix pump + the M4.6 off-route → auto-reroute chain) still
      lives in `MapFullScreenView` and runs while that screen is on-screen —
      routing / navigation algorithms are unchanged.
      `makeFullScreenView()` hands back a **cached** `AnyView` so an unrelated
      shell `body` re-render can't rebuild the map under a live session; leaving
      Maps entirely still tears the `GMSMapView` down and rebuilds it on return
      from the persisted state.

34. **Dashboard layout foundation (M5.2.0).**
    The widget dashboard's arrangement + persistence, with **no** component
    rendering, editing, drag/resize, or new features yet. Chain:
    `DashboardShell → DashboardLayoutStore → DashboardLayout → WidgetPlacement →
    FeatureRegistry → DashFeature.makeComponentView(size:)` (still a placeholder).
    - **Fixed grid, shell-owned footprints (`DashboardGrid`).** A page is a
      **6-column × 4-row** cell grid (`DashboardGrid.standard`). A placement
      stores only `size` + `origin: GridPoint`; the **shell** turns
      `ComponentSize` into cells — `.compact` 2×1, `.medium` 3×2, `.large` 6×2,
      `.full` = whole grid (not a valid widget). Grid dimensions never touch
      `MapFeature`. `GridRect.intersects` + `DashboardGrid.contains` are pure.
    - **SDK-neutral `Codable` model (`DashboardLayout`).** Ordered
      `[DashboardPage]`, each ordered `[WidgetPlacement]` =
      `{ id: UUID, featureID, size, origin }`. Placement identity is part of
      `Equatable` and survives `Codable` round-trips. `page(at:)` is
      bounds-checked; `allPlacements` flattens in order.
    - **Validation is a pure enum namespace (`DashboardLayoutValidator`), not
      the store's job.** `validate(_:grid:)` — duplicate id / non-widget size /
      out-of-bounds / per-page overlap. `@MainActor validate(_:grid:registry:)`
      adds unknown-feature / unsupported-size. The store *uses* the structural
      check as a load-time gate; it does not contain the rules.
    - **Persistence: a schema-versioned envelope (`DashboardLayoutStore`).**
      `@MainActor ObservableObject`. Writes `{ version: Int, layout }` as JSON
      under **`shell.dashboardLayout.v1`** in `UserDefaults` (the `.vN` in the
      key is the breaking-change lever; the envelope `version` — currently **1**
      — guards the current line). `init` returns the persisted layout **only**
      if it exists, decodes, `version == schemaVersion`, *and* passes the
      structural validator — otherwise the injected **seed**. `replace(with:)` /
      `resetToDefault()` are the save path; nothing calls them in M5.2.0 (no
      editing UI). First run persists nothing, so a later default still applies.
      No runtime feature state is stored here.
    - **`DashboardSpaceView` replaces `DashboardPlaceholderView`.** Reads the
      store, resolves `featureID` through `FeatureRegistry`, calls
      `DashFeature.makeComponentView(size:)`, absolute-positions each widget on
      the grid from a `GeometryReader`, and shows prev/next + page dots when
      `pageCount > 1`. Unknown feature / unsupported size / `.full` →
      a labelled `UnresolvedWidgetView`. `resolvedPageIndex` clamps the shell's
      requested page.
    - **Default layout: two pages, Maps only** (`DashApp` seeds
      `DashboardLayout.starter(featureID: MapFeature.id)`). Page 1: `.large` at
      (0,0), `.medium` at (0,2), `.compact` at (3,2). Page 2: `.large` at (0,0),
      `.medium` at (0,2). Demonstrates multiple sizes / positions / pages
      without inventing fake features. A test asserts it validates clean against
      the real registry.
    - **Boundaries.** `DashboardShell` gains only `@EnvironmentObject
      layoutStore` + a `DashboardGrid` constant + the `.dashboard(page:)` →
      `DashboardSpaceView` wiring. `page` navigation is `ShellSurface.dashboard(page:)`
      + `ShellStore.goToPage` (already there since M5.0). `MapFeature` unchanged.
    - **Device-verified** on the physical iPad (placeholder widgets render on the
      grid; page navigation works). Full suite **347/347**, build clean. +24
      unit tests. §3, §10.

---

## 6. Current limitations / known issues

- **Dashboard is structural, not visual (M5.0–M5.2.0).** The shell (sidebar +
  Home + Dashboard spaces), the widget grid, its persistence, and full-screen
  Maps all work, but: the Home launcher and the dashboard widgets are
  deliberately plain placeholders; there is still **no theming / `ThemeManager`**,
  no hidden-iPadOS-chrome pass, no landscape lock, and **no "GPS signal lost"
  banner** (the `LocationStore.signal` state exists but nothing displays it).
- **Dashboard widgets are placeholders (until M5.2.1).**
  `MapFeature.makeComponentView(size:)` returns a labelled placeholder — the
  compact/medium/large Map presentations are not built. `DashFeature` only has
  the Map feature registered; Speedometer / Music / Settings don't exist yet.
- **No dashboard editing.** `DashboardLayoutStore.replace(with:)` /
  `resetToDefault()` are the only ways to change the layout and nothing calls
  them — there is no drag / resize / add / remove UI. The default two-page
  layout is what every run shows. `DashboardLayout` schema is versioned (`v1`)
  so a later grid or size-semantics change needs migration code, not a silent
  reset of a user's arrangement.
- **`DashboardShell` mounts one map view at a time.** Only the visible surface's
  views are mounted, so leaving Maps dismantles the `GMSMapView` and returning
  rebuilds it (from the persisted `MapFeature` state — the route / nav session
  is intact, but there is a brief re-init). A widget-sized live map + the
  full-screen map are never on screen together in M5.2.0 (widgets are
  placeholders).
- **DashRelay UI is minimal.** `RelayStatusScreen` now shows the session state
  (stopped / waiting / connected) with Start and Disconnect actions, but there is
  **no last-sent-timestamp / packet-rate display** (spec §3 asks for "Relay
  active + last-sent timestamp"), **no connected-device name** (see decision 18),
  and the visuals are deliberately plain.
- **Connection/pairing UI is functional but not designed.** `ConnectionSetupView`
  covers the device picker + "name this iPhone" prompt, "Looking for `<paired>`…",
  "Stop Searching", and "Forget `<name>`"; `ConnectedControlView` covers
  disconnect/forget while connected; DashRelay has "Stop Sharing"/"Disconnect".
  Visuals are still deliberately plain, there is no "GPS signal lost" overlay on
  the dashboard, and the dashboard is still torn down on any brief drop (see
  decision 17). None of this round's UI has had a simulator/visual pass (see §3).
- **No in-place rename of a paired relay.** The friendly name is captured once at
  pairing; to change it the user must Forget and re-pair. `KnownDeviceStore` /
  `KnownRelay` already support updating `displayName` in place — only the UI
  affordance is missing.
- **`ConnectedControlView` now lives in the shell sidebar** (M5.0 moved it there
  from the old `RootView` overlay). Disconnect / Forget behaviour is unchanged;
  the placement is functional, not visually designed.
- **Pairing works but is single-device in practice.** `KnownDeviceStore` holds a
  list and `ConnectionCoordinator` auto-connects only when *exactly one* known
  relay is visible, but there is **no chooser among several known devices** —
  `pairedRelay` is just the first. `forgetAll` exists in the store but isn't
  surfaced. Restricting connections to *only* known devices is enforced
  implicitly (the receiver targets one id) but there is no explicit allow-list.
- **A DashRelay reinstall changes the relay id**, so the iPad silently stops
  finding the "paired" phone until the user re-pairs (`Forget` → pick again). No
  UI hint that this is why. Acceptable per decision 19; worth a nicer message
  later.
- **`LocationReceiver`'s Bonjour/TCP internals remain unit-untested.** The TXT
  parsing, `setTargetRelay` connect/re-target logic, and reconnect-to-same-id
  behaviour are only exercised on device / by the `ConnectionCoordinator` stub
  tests. `RelayAdvertisement` parsing itself is unit-tested in `DashShared`.
- **Partly-exercised map plumbing.** As of M3 `MapContent.markers` (M2 pin),
  `MapContent.polylines` (M3 route), the `.fit` camera plan, and
  `MapMode.destinationPreview` are all driven. Still inert until later milestones:
  `.navigating` mode, and every `MapEvent` case — `MapViewModel.handle(_:)` is
  still a no-op, so a POI tap on the map does **not** yet become a destination
  (only the search field does).
- **M3: the preview camera re-fits once per route, not continuously.** When a
  route loads it re-frames to fit vehicle + destination + route; it does **not**
  keep re-fitting as the vehicle moves along the route (that is navigation camera
  behaviour, M4). If the vehicle drives well past the framed box before "start
  navigation" exists, the view will not follow.
- **M3: no automatic route retry when GPS arrives.** If a destination is chosen
  before the first fix, the state is `.noCurrentLocation` and stays there until
  the user taps Retry (or re-selects). Deliberate — M3 has no location observer
  in the routing layer and no auto-reroute.
- **M4.6: off-route detection projects onto the overview polyline.**
  `OffRouteDetector` measures the vehicle against `route.polyline` (the coarser
  overview geometry, not the per-step polylines), same as the M4.4 route clip.
  On a route that doubles back close to itself the projection can jump. The
  2026-09-03 refinement tightened the thresholds (35 m, 3 consecutive fixes) for
  a snappier response; the hysteresis band + 3-fix confirmation still keep a
  burst of bad GPS from triggering, but the tighter numbers have **not** been
  run against a real drive that misses a turn yet — that check is the main open
  item for M4.6.
- **M4.6: after an automatic reroute the alternatives are not offered as a
  chooser.** The recommended route is adopted and the alternatives remain in
  `MapViewModel.routeOptions` (drawn dimmed on the map, tappable only in
  preview), but no `RouteOptionsPanelView` is shown mid-navigation for them —
  consistent with the M4.5 decision that a stray tap while driving can't switch
  the active route. The driver can still hit the manual Refresh.
- **M4.6: a cooldown collision can delay a second reroute.** If the vehicle is
  off the *new* route within `autoRerouteCooldownSeconds` (25) of the last
  automatic reroute, the detector re-signals (every 8 fixes) but `autoReroute`
  refuses until the cooldown elapses — up to ~25 s to the next attempt. Rare
  (the adopted route normally passes through the current position) and
  conservative by design.
- **M4.6 / M5.1: `NavigationViewModel` still does not observe `LocationStore`.**
  The off-route detector, like progress, only advances while `MapFullScreenView`
  pumps fixes into `update(with:)`. Since M5.1 the Map screen is no longer the
  only screen — leaving Maps (e.g. to Home) **freezes** nav progress / off-route
  detection until you return (the session *state* is preserved, not advanced).
  Moving the pump into `MapFeature` (feature observes `LocationStore`) is the
  natural follow-up; deliberately not done in M5.1.
- **M4.3: wrong-turn *guidance* still lags until rejoin.** With M4.6 the app now
  recomputes a route when the driver leaves it, but between the missed turn and
  the adopted route the maneuver card can still show the stale maneuver (the
  ~80 m progress-engine off-route-ignore threshold stops a noisy fix from
  *skipping* maneuvers; it does not re-anchor guidance).
- **M4.3: `NavigationViewModel` does not observe `LocationStore` itself.**
  `MapFullScreenView` pumps each fix into `navVM.update(with:)` and relays
  `progress` to `MapViewModel` — consistent with `RouteViewModel`. See the
  M5.1 note above: this now means progress freezes while the Map screen is off.
- **M4.3: road names are parsed from instruction text.** The Routes API gives no
  dedicated street field per step, so `roadName` comes from an "onto/on/toward"
  heuristic on the instruction string. It handles the common phrasings; unusual
  instructions fall back to showing the full instruction with no separate road
  line.
- **M4.3: the maneuver arrow set is approximate.** `ManeuverType.symbolName`
  maps to SF Symbols; a few (sharp turns, forks, ramps) reuse near-neighbours
  rather than exact glyphs.
- **M4.4: ETA is a proportional estimate, not traffic-aware.** Remaining time =
  route duration × (distance left ÷ total). It tracks distance faithfully but
  does not react to congestion, and it assumes a roughly constant average speed
  along the route. A live traffic ETA needs `routingPreference: TRAFFIC_AWARE`
  on the Routes request (a billing change) and is a later task.
- **M4.4: the preview ETA only refreshes every ~30 s.** It is inside a
  `TimelineView(.periodic(by: 30))`, so a preview left open ticks over on a
  ~30 s cadence rather than exactly on the minute. During navigation it also
  refreshes on each GPS fix.
- **M4.3: no trip panel / average speed.** `Route.duration` /
  `distanceRemainingMeters` now feed the info panel, but there is still no
  average / max speed or elapsed-time trip computer (that's the Speedometer
  milestone).
- **M4.4-polish: the shortened route line snaps to the overview polyline.**
  `remainingPolyline` projects the vehicle onto `route.polyline` (the overview
  geometry, ~coarser than the per-step polylines). On a route that doubles back
  close to itself the projection can jump, briefly clipping the wrong part.
  M4.6's `OffRouteDetector` shares this projection basis (and the same caveat).
  Fine for ordinary routes.
- **M4.4-polish: the navigation camera anchor is a fixed fraction.**
  `vehicleVerticalAnchor = 0.6` is not aware of the actual on-screen panel /
  maneuver-card heights or the device aspect ratio — it is a constant chosen to
  clear them comfortably in both orientations, not a computed inset.
- **M4.5: Google may return only one route.** `computeAlternativeRoutes` is a
  hint — the API often returns a single route for short / unambiguous trips. The
  app degrades to the M4.4 single-route behaviour (no selector, one polyline);
  this hasn't been checked against the live API yet, only canned responses.
- **M4.5: refreshed alternatives can go stale.** After a mid-navigation *manual*
  refresh, the alternatives are computed from that moment's position and keep
  drawing (dimmed) as the drive continues. There is no re-evaluation — the
  driver either adopts one or dismisses. (M4.6 adds *automatic* off-route
  rerouting, which adopts the recommended route straight away rather than
  leaving a set on screen.)
- **M4.5: adopting a refreshed route re-seeds progress from the *current*
  position.** If the current fix is momentarily off the new route's geometry,
  `NavigationProgressCalculator.initial` still snaps to the nearest point — fine
  in practice, but there is no validation that the driver is actually on the
  adopted route.
- **M4.5: `Route.id` is response-index based.** `"route-<n>"` is unique within a
  response but not across refreshes — a refreshed set reuses `"route-0"…`. That
  is intentional (the map keys by it within one render) but means ids are not
  globally meaningful.
- **M4.2: gesture detection trusts `willMove(byGesture:)`.** Any user
  pan/zoom/rotate drops follow — there is no distance/zoom threshold (the
  earlier `isMeaningfulMove` heuristic was removed 2026-09-02 after device
  testing showed small/fast gestures slipping through). This means follow relies
  entirely on GMS setting the `byGesture` flag correctly; if a future SDK version
  mislabels a programmatic move as a gesture it would spuriously drop follow
  (recenter always restores it). Programmatic-only moves never latch the gesture
  state, so there is still no feedback loop.
- **M4.2: no heading smoothing in the navigation camera either.** The camera
  bearing is the raw latest `LocationPacket.heading`; same jitter caveat as the
  indicator below.
- **M4.1: no heading smoothing.** The pointer snaps to the raw latest
  `LocationPacket.heading`; at low speed / poor GPS it can jitter. Smoothing was
  explicitly out of scope for this task.
- **M4.1: the vehicle-marker drawing is device-validated only.** The dot/pointer
  *decision* (`vehicleStyle`) is unit-tested, but the code-drawn `UIImage`s, the
  `isFlat` marker, and `marker.rotation` = bearing are only exercised on a real
  `GMSMapView`.
- **M2 autocomplete is device-verified; the rest of the map/search UI is not.**
  On the physical iPad, `GooglePlaceSearchService.suggestions(...)` +
  `mapSuggestion` field mapping + the `MapSearchView` suggestion list are
  confirmed working against the live **Places API (New)** (§3). Still only
  unit-covered + clean-build: `details(for:)` Place Details resolve, the
  destination pin, the `.destinationPreview` camera framing, and the
  `GoogleMapProvider` delegate/diffing rewrite (M1).
- **`GMSFetchPlaceRequest` / Place Details (New) is still unverified against the
  live service.** The property strings, session-token hand-off from autocomplete,
  and error mapping are coded to the 11.1.0 headers; only autocomplete has been
  exercised on device so far.
- **Debounce + async search timing is only lightly covered.** Tests use a
  `.zero` debounce and `await` the pending task; real rapid typing / cancellation
  behaviour on device isn't proven.
- **`GooglePlacesSwift` (preview) is downloaded but unused.** The `ios-places-sdk`
  SPM package vends both `GooglePlaces` and `GooglePlacesSwift`; only the former
  is linked, but SwiftPM still fetches both xcframeworks.
- **Landscape-primary not configured.** All four iPad orientations are currently
  allowed; the "landscape is primary" intent isn't reflected in Info.plist.
- **End-to-end transfer is not covered by automated tests.** It has been
  verified manually on device (§3) but a clean CI checkout cannot prove it.
- **Background reliability not independently verified in this repo.** The
  Info.plist keys and `CLLocationManager` configuration match the spec's
  requirements, but sustained backgrounded/locked relaying over a long drive is a
  device-only behaviour and is not something the repo demonstrates.
- **`GMSMapView` created via `GMSMapView()`** relies on `GMSServices.provideAPIKey`
  having run first (`DashApp.init()` / the SwiftUI preview handle this). If the
  key is missing, the SDK logs and the map fails to authenticate.
- **`AnyView` in the map boundary** is a deliberate simplification; if SwiftUI
  identity churn ever causes the `GMSMapView` to be recreated, this is the place
  to revisit.
- **Scaffold `DashTests.example()`** is a no-op still counted in the suite.
- **Deployment-target split** (apps 18.6, test bundles 26.5) is untidy and could
  bite when running tests on an older physical device.
- **`ThemeManager`, `TripStats`, `SettingsStore`** from the spec's intended
  structure do not exist yet.
- **M5.2.0: `DashboardSpaceView` uses absolute `.offset` positioning**, not a
  real grid-layout container — fine for fixed placements, but a drag/resize
  editor will likely want a proper `Layout` or coordinate-space approach.
- **M5.2.0: the store's load-time validation is grid-only** (no registry, by
  design). A persisted layout referencing a since-removed feature still loads;
  the shell renders `UnresolvedWidgetView` for those placements. Registry-aware
  pruning would couple the store to `FeatureRegistry` — deferred.
- **M5.2.0: `.compact` (2×1) on a 6-wide grid** leaves a spare column when three
  are in a row; the size → span table is the one place to tune once real
  components land (M5.2.1).

---

## 7. Not yet implemented

From `PROJECT_SPEC.pdf` / `CLAUDE.md`, still absent from the repo:

- **[Implemented]** iPad connection/session state machine
  (`ConnectionCoordinator`) **and** its first UI (`ConnectionSetupView` +
  `RootView` gate) — see §3. **Still [Planned]** on top of it: a watchdog "GPS
  signal lost" overlay on the dashboard, keeping the dashboard up during brief
  reconnects instead of falling back to the setup screen, and a designed visual
  pass.
- **[Implemented]** DashRelay connection/status screen (`RelayStatusScreen` /
  `RelayStatusView`) — stopped / waiting / connected with Start + Disconnect —
  see §3. **Still [Planned]** on top of it: a **last-sent-timestamp / "relay
  active" indicator** (spec §3), a connected-device name (needs new session-layer
  plumbing, decision 18), and a designed visual pass.
- **[Implemented]** Device **pairing flow** — stable TXT-record identity
  (`RelayAdvertisement` / `RelayIdentity`), discover-then-pick first-time setup
  with a friendly-name prompt, auto-prefer the paired relay on later launches,
  never switch to a stranger, Disconnect (keeps pairing) reachable while
  connected, and `forgetPairedRelay()` — see §3 and decisions 19–23. First-time
  pair verified on hardware (§3 "End-to-end"). **Still [Planned]** on top of it:
  a chooser among *several* known devices, in-place rename, a designed
  Forget/settings surface, a friendlier "your paired iPhone changed /
  reinstalled" message, and on-device verification of the *remaining* behaviours
  (§6).
- **[Implemented · device-verified]** The CarPlay-style shell — realised as
  `DashboardShell` + `Shell/` (M5.0), with app-scoped Map state (M5.1) and the
  widget-grid layout foundation (M5.2.0, §5 items 33–34). The single layout
  owner; replaced the `RootView → ContentView` full-screen-map shell. **Still
  [Planned]** on top of it: real Map dashboard components at each `ComponentSize`
  (M5.2.1), a real multi-page/reorderable Home launcher, dashboard editing
  (drag/resize/add/remove), a "GPS signal lost" banner, and a designed visual
  pass.
- **[Planned]** `ThemeManager` — dark/light auto-switch by local sunrise/sunset.
- **[Planned]** Hide iPadOS chrome: full-screen, `isIdleTimerDisabled = true`,
  no nav bars / default list styling.
- **[Planned]** Speedometer (`SpeedometerView`) — big numeral/gauge, m/s → km/h,
  rolling-average smoothing of the last 2–3 readings.
- **[Planned]** Trip computer (`TripComputerViewModel` + `TripStats`) — running
  distance, elapsed time, avg/max speed, reset on new drive. *(Explicitly out of
  scope for current work — no route/trip logic yet.)*
- **[Planned]** Music (`MusicPlayerView` + `MusicPlayerViewModel`) — MusicKit
  full-catalog search + custom player UI.
- **[Planned]** `AppleMapProvider` (MapKit) — the second `MapProvider`
  implementation. See §10 for exactly what this touches.
- **[Planned]** `SettingsView` + `SettingsStore` — map-provider toggle persisted
  in `UserDefaults`.
- **[Implemented]** Map rendering boundary for overlays + events + modes
  (§5 item 24): `MapContent`, `MapEvent`, `MapMode`, `MapCameraPlan.fit`.
  `.markers` / `.polylines` / `.fit` / `.destinationPreview` are all driven as of
  M3; `.navigating` mode and `MapEvent` consumption still await navigation.
- **[Implemented]** Destination search (§5 item 25): `PlaceSearchService` +
  `GooglePlaceSearchService` (Places SDK), `PlaceSearchViewModel`,
  `DestinationStore`, `MapSearchView`, `MapViewModel.setDestination(_:)`.
  "Places API (New)" is enabled and autocomplete is device-verified (§3);
  Place Details resolve + pin + preview camera are still device-unverified (§6).
- **[Implemented · device-verified]** Routing (§5 item 26): `RouteService` +
  `GoogleRouteService` (Routes API, REST), `Route` / `GooglePolyline`,
  `RouteViewModel`, `RouteStatusView`, `MapViewModel.setRoute(_:)`. Routes API
  enabled + authorised; live request + polyline confirmed on the iPad (§3, §10).
  Committed `28b5be5`.
- **[Implemented · device-verified]** M4.1 current-location indicator (§5 item
  27): `VehicleIndicator`, `GoogleMapProvider.vehicleStyle` + the blue dot /
  rotating pointer rendering. Device-verified, committed `8255749`.
- **[Implemented · device-verified]** M4.2 camera follow / manual pan-zoom /
  recenter (§5 item 28): `MapViewModel.followsVehicle`, `recenter()` /
  `showsRecenterButton`, `RecenterButton`, `MapCameraPlan.navigation`,
  provider-side user-gesture detection (`GoogleMapProvider.UserGestureLatch` over
  `willMove(byGesture:)`, no threshold). Committed `d8b291e`.
- **[Implemented · device-verified]** M4.3 start navigation & maneuver guidance
  (§5 item 29): `Route.steps` / `RouteStep`, `GoogleRouteService` step + maneuver
  mapping, `RouteGeometry` / `NavigationProgressCalculator` / `NavigationViewModel`,
  `ManeuverCardView` / `StartNavigationButton`, `MapViewModel.startNavigation()` +
  dynamic navigation zoom. Physically verified on the iPad (§3, §10). Committed
  `a262a9c`.
- **[Implemented · device-verified]** M4.4 route info & ETA + the camera /
  route-clip / layout polish pass (§5 item 30). Committed `4697557`.
- **[Implemented · device-verified]** M4.5 multiple route options + manual route
  refresh (§5 item 31): `RouteService.routes(...) -> [Route]` +
  `computeAlternativeRoutes`, `RouteOptions`, `RouteViewModel` (`loaded(RouteOptions)`
  + `refresh`), `MapViewModel.setRouteOptions` / `selectRouteOption`,
  `MapPolyline.role`, `MapEvent.tappedRoute`, `NavigationViewModel.reroute`,
  `RouteOptionsPanelView`, the maneuver-card Refresh button. Committed `678e478`.
- **[Implemented · unit-tested, device-unverified]** M4.6 smart off-route
  detection + automatic rerouting (§5 item 32; 2026-09-03 refinement folded in):
  `OffRouteDetector` (pure, reuses `RouteGeometry.project`; thresholds 20 / 35 /
  3), `NavigationViewModel.offRouteStatus` / `needsAutomaticReroute` + detector
  re-arm, `RouteViewModel.autoReroute(from:)` + `@Published refreshWasAutomatic`
  + derived `isAutomaticallyRecalculating` + `canAutoReroute` cooldown (shared
  `refresh` field / task with the manual path), `ContentView` off-route →
  auto-reroute → recommended-route adoption + the synchronously-shown
  "Recalculating…" pill. +38 unit tests; a live missed-turn drive is pending
  (§3, §10). Committed `73879e7`.
- **[Planned]** Map layer depth, remaining (the rest of **M4**): a
  **traffic-aware** ETA (`routingPreference: TRAFFIC_AWARE` — a billing change),
  voice guidance, lane guidance. Also: turning a map POI tap
  (`MapEvent.tappedPOI`) into a destination; an Apple `MKDirections`
  `RouteService`.
- **[Planned]** Dock-style row of favourite/frequent destinations.
- **[Future idea]** Weather widget (WeatherKit free tier).
- **[Future idea]** Parking-location auto-pin on Bluetooth disconnect.
- **[Future idea]** Voice control (SiriKit / App Shortcuts / Speech).
- **[Future idea]** Incoming-call handling (possibly free via Continuity).

---

## 8. Next planned milestones

Roughly in order (adapts the spec §11 build order to where we are):

1. **Finish device verification of the connection UX.** First-time pair is
   confirmed on hardware (no diagnostic logging remains in the source).
   Still to check on device: auto-prefer the paired relay across a DashRelay
   relaunch, "Looking for `<name>`…" when it's absent, Disconnect / Forget /
   "Stop Searching" / DashRelay "Stop Sharing", the "name this iPhone" prompt,
   `ConnectedControlView` in both orientations, and two physical relays being
   disambiguated.
2. **Connection UI, continued.** A "GPS signal lost" overlay driven by
   `LocationStore.signal`, keep the dashboard visible during brief incidental
   drops (only fall back to setup after a sustained/deliberate disconnect), a
   designed visual pass over the connection screens + the connected control,
   in-place rename, and a chooser among *several* known devices.
3. **DashRelay status screen, continued.** Basic screen is done
   (`RelayStatusScreen` / `RelayStatusView`). Remaining: a last-sent-timestamp /
   "relay active" indicator (spec §3), and — once the session layer exposes it —
   the connected Dash device's name.
4. **The CarPlay-style shell — done through M5.2.0** (`DashboardShell` + `Shell/`,
   app-scoped Map state, the widget-grid layout foundation; §5 items 33–34).
   **Next: M5.2.1** — real Map dashboard components at each `ComponentSize`
   (`MapFeature.makeComponentView(size:)`): `.large` = interactive `DashMapView`;
   `.medium` = reduced map + next maneuver + ETA (throttled, tap to open full);
   `.compact` = maneuver card / favourites dock, no tiny map. After that:
   a real multi-page/reorderable Home launcher, dashboard editing
   (drag / resize / add / remove) with the `DashboardLayoutValidator` gating it,
   the "GPS signal lost" banner, `ThemeManager`, hidden iPadOS chrome,
   landscape-primary config.
5. **Speedometer + trip computer** — a `SpeedometerFeature` derived from
   `LocationStore` (smoothing, km/h, `TripStats`); a good second real feature to
   prove the registry + sizing.
6. **Music** — a `MusicFeature` (MusicKit catalog search + custom player).
7. **`AppleMapProvider` + `SettingsFeature`** — second provider, persisted choice.

Map-feature sub-track (independent of the above ordering; **M1–M4.6 committed;
dashboard shell M5.0 + M5.1 committed; M5.2.0 in the working tree**):
- **M1 [done]** — widen the rendering boundary for overlays / events / modes
  (§5 item 24).
- **M2 [done, device-verified for autocomplete]** — `PlaceSearchService` + Google
  impl, custom `MapSearchView`, destination pin + preview camera (§5 item 25).
  Still to check on device: Place Details resolve, the pin, the preview camera (§6).
- **M3 [done, device-verified, committed `28b5be5`]** — `RouteService` +
  `GoogleRouteService` (Routes API, once per selection), `Route` /
  `GooglePolyline` / `RouteViewModel` / `RouteStatusView`, route polyline via
  `MapViewModel.setRoute(_:)`; live request + polyline confirmed on the iPad
  (needed the `X-Ios-Bundle-Identifier` header). §5 item 26.
- **M4.1 [done, device-verified, committed `8255749`]** — provider-neutral
  `VehicleIndicator` + navigation-style current-location rendering in
  `GoogleMapProvider` (blue dot / rotating pointer from `LocationPacket.heading`).
  §5 item 27. **Indicator only** — no follow camera.
- **M4.2 [done, device-verified, committed `d8b291e`]** — provider-neutral
  `followsVehicle` state, `RecenterButton`, threshold-free user-gesture detection
  in `GoogleMapProvider` (`UserGestureLatch` over `willMove(byGesture:)`), and the
  `MapCameraPlan.navigation` framing. §5 item 28. **Camera framing only.**
- **M4.3 [done, device-verified, committed `a262a9c`]** — `Route.steps` /
  `RouteStep`, `GoogleRouteService` step + maneuver mapping, the pure
  `RouteGeometry` / `NavigationProgressCalculator` engine, `NavigationViewModel`,
  the `ManeuverCardView` + `StartNavigationButton`,
  `MapViewModel.startNavigation()` and the quantised dynamic navigation zoom.
  §5 item 29. **Guidance display + camera only.**
- **M4.4 [done, device-verified, committed `4697557`]** — `RouteFormat` +
  `Duration.inSeconds`, `NavigationProgress.remainingDuration(along:)`,
  `RouteInfo`, `RouteInfoPanelView`, `NavigationViewModel.routeInfo(now:)`, the
  `ContentView` bottom panel, plus the camera-anchor / route-clip / preview-row
  polish. §5 item 30.
- **M4.5 [done, committed `678e478`]** — `RouteService.routes(...) -> [Route]` +
  `computeAlternativeRoutes`, `RouteOptions`, `RouteViewModel` (`loaded(RouteOptions)`
  + manual `refresh`), `MapViewModel.setRouteOptions` / `selectRouteOption`,
  `MapPolyline.role`, `MapEvent.tappedRoute`, `NavigationViewModel.reroute`,
  `RouteOptionsPanelView`, the maneuver-card Refresh button. §5 item 31.
- **M4.6 [done, unit-tested (+38), committed `73879e7`; 2026-09-03 refinement
  folded in; live missed-turn drive still pending]** — pure `OffRouteDetector`
  (onRoute / possiblyOffRoute / confirmedOffRoute, thresholds **20 / 35 / 3**,
  hysteresis, consecutive-fix confirmation, re-signal), `NavigationViewModel`
  off-route signal + detector re-arm, `RouteViewModel.autoReroute` (current
  origin, shared `refresh` field/task, `@Published refreshWasAutomatic` +
  `isAutomaticallyRecalculating`, 25 s cooldown), off-route → auto-reroute +
  recommended-route adoption + synchronously-shown "Recalculating…" pill. §5
  item 32. **Detection + auto-reroute only** — no traffic, no polling, no voice.
- **M4.7+** — a **traffic-aware** ETA (`TRAFFIC_AWARE`); then heading smoothing,
  voice guidance, and the POI-tap → destination path.

Dashboard sub-track (§5 items 33–34):
- **M5.0 [done, committed `258ffde`]** — the shell / feature seam: `DashFeature`
  / `FeatureManifest` / `FeatureRegistry` / `ComponentSize`, `ShellSurface` /
  `ShellStore`, `DashboardShell` + `SidebarView` + placeholder Home,
  `MapFeature` wrapping the full-screen map, `ConnectedControlView` moved to the
  sidebar. +23 unit tests.
- **M5.1 [done, committed `e8e913f`]** — Map runtime state moved onto `MapFeature`
  (app-scoped); `ContentView` → `MapFullScreenView` (observes, doesn't own).
  A nav session now survives Maps → Home → Maps. +6 unit tests.
- **M5.2.0 [done, working tree, device-verified]** — the widget-grid layout
  foundation: `DashboardGrid` (6×4 + footprints), `DashboardLayout` /
  `WidgetPlacement`, `DashboardLayoutValidator`, `DashboardLayoutStore`
  (`shell.dashboardLayout.v1`), `DashboardSpaceView` (replaces the placeholder),
  the two-page Maps starter layout. +24 unit tests. §5 item 34.
- **M5.2.1 [next]** — real `MapFeature.makeComponentView(size:)` per
  `ComponentSize`. Then Home / editing / theming / chrome (item 4 above).
8. **Polish pass** — `ThemeManager`, idle-timer disable, hide iPadOS chrome,
   favourites dock, landscape-primary orientation config.

---

## 9. Important configuration / secrets notes

### Google Maps API key

- **Never in source.** The key flows:
  `Dash/Config/GoogleMapsService.xcconfig` (build setting `GOOGLE_MAPS_API_KEY`)
  → `Dash/Dash/Info.plist` key `GoogleMapsAPIKey = $(GOOGLE_MAPS_API_KEY)`
  → `GoogleMapsConfiguration.apiKey` reads it from the bundle at runtime
  → `GoogleMapsConfiguration.bootstrap()` calls `GMSServices.provideAPIKey(_:)`
  **and** `GooglePlacesConfiguration.bootstrap()` calls
  `GMSPlacesClient.provideAPIKey(_:)` with the **same** key (one key covers every
  Google Maps Platform API for this bundle). Both invoked from `DashApp.init()`
  and the `ContentView` preview.
- `Dash/Config/GoogleMapsService.xcconfig` is **git-ignored** (`.gitignore` at
  repo root). It is wired as the `baseConfigurationReference` for the Dash target's
  Debug and Release configs.
- `Dash/Config/GoogleMapsService.xcconfig.template` is committed. A fresh
  checkout: `cp Dash/Config/GoogleMapsService.xcconfig.template Dash/Config/GoogleMapsService.xcconfig`
  then paste the key. In CI, set `GOOGLE_MAPS_API_KEY` as a build/env variable
  instead.
- With no key, the app still builds and runs; `GoogleMapsAPIKey` resolves to `""`,
  `GoogleMapsConfiguration.apiKey` returns `nil`, and the map won't authenticate.
- **A working key is currently present in the developer's local (un-committed)
  `GoogleMapsService.xcconfig`.** It is not in the repo. Treat it as a secret; if
  it ever leaks, rotate it in Google Cloud console. Consider a $1 billing budget
  alert (spec §5) and per-app-bundle-ID / API restrictions on the key.

### Google Cloud — required for M2 (destination search)  ✅ confirmed working

Confirmed on the physical iPad (2026-09-02): autocomplete requests against
**Places API (New)** succeed with the existing Maps key, so in the developer's
Google Cloud project:

1. **"Places API (New)" is enabled** (distinct from the legacy "Places API"). The
   Maps SDK for iOS API was already enabled.
2. **The iOS API key's "API restrictions" allow Places API (New)**, keeping the
   existing bundle-ID application restriction (`com.sakshamsharma.Dash`). No new
   key was needed.
3. No new Info.plist keys, entitlements, or usage strings are required for search.
   (Routing additionally needs the **Routes API** enabled — done and confirmed,
   see below.)

If Places access were ever revoked, autocomplete / details requests return an
error and `PlaceSearchViewModel` shows its generic "Couldn't search" text.

### Google Cloud — required for M3 routing / M4.3 turn-by-turn / M4.5 alternatives  ✅ confirmed working

`GoogleRouteService` calls the **Routes API** — a **third** Google Maps Platform
API, separate from the Maps SDK for iOS and Places API (New). Confirmed on the
physical iPad (2026-09-02): a live `computeRoutes` request succeeds, so in the
developer's Google Cloud project:

1. **The "Routes API" is enabled.**
2. **The iOS API key's "API restrictions" allow the Routes API**, keeping the
   existing `com.sakshamsharma.Dash` bundle-ID application restriction. The REST
   call sends the key in `X-Goog-Api-Key` **and** the bundle id in
   `X-Ios-Bundle-Identifier` so the restricted key is accepted (M3 device fix).
3. No Info.plist / entitlement / ATS changes — `routes.googleapis.com` is plain
   HTTPS.

**M4.3 note:** requesting `routes.legs.steps.*` (the turn-by-turn maneuvers) moves
the call from the Routes "Basic" SKU to **"Advanced"**. Still comfortably inside
the free tier at one user × once-per-trip (~60–90/month); the $1 budget alert
covers it either way. If step billing ever becomes a concern, the field mask is
the single place to trim.

**M4.5 note:** `computeAlternativeRoutes: true` returns up to ~3 routes in one
response — **one request, same SKU** (it is not billed per alternative). A
manual "Refresh Route" is one more request; there is no polling. Still
`TRAFFIC_UNAWARE` — no traffic-tier pricing.

### Google Maps cost discipline (spec §5)

- Maps SDK map view: free/unlimited.
- Places **Autocomplete**: free ≤ 10k requests/month; a `GMSAutocompleteSessionToken`
  groups a keystroke run + the details fetch into one cheaper billing session
  (the Google impl already does this). Comfortably free at single-user volume.
- Places **Details (New)**: billed per field group; one call per chosen
  destination — negligible at this volume.
- **Routes API "Compute Routes"** (M3–M4.6): billed **per request**.
  `RouteViewModel` fires one request per destination selection / Retry, plus at
  most one manual **Refresh Route** (M4.5), plus an **automatic off-route
  reroute** (M4.6) — the latter is gated by a 25 s cooldown, so a badly
  off-route drive costs at most ~1 extra request every 25 s (typically 1–2 for a
  whole trip); there is still **no timer / polling**. `startNavigation()` reuses
  the already-loaded route. `computeAlternativeRoutes` returns the alternatives
  in that same one request. `TRAFFIC_UNAWARE` keeps traffic pricing off; the
  field mask adds `routes.legs.steps.*` (→ "Advanced" SKU). ~60–90 trips/month
  is within the monthly free allowance. Traffic-aware ETA / voice guidance are
  still later work.

### Signing / distribution

- Paid Apple Developer account, team `LGQX79QMNJ`, automatic signing. Personal
  use, sideloaded, **no App Store**.

### Networking permissions

- Both apps ship `NSLocalNetworkUsageDescription` and
  `NSBonjourServices: [_dashrelay._tcp]`. DashRelay additionally ships the
  location usage strings and `UIBackgroundModes: [location]`. The "Location
  updates" background capability is expressed via Info.plist (confirm it shows
  checked in Xcode's Signing & Capabilities if the project is re-opened).

---

## 10. Recent milestone history

Git history on `main` (newest first):

| Commit | Milestone |
|---|---|
| *(working tree, uncommitted)* | **Dashboard "M5.2.0": widget-grid layout foundation** (2026-09-03) (layout + persistence only — **no** Map component rendering, editing / drag / resize, Speedometer, Music, `ThemeManager`, wallpapers, battery/network status, or navigation changes). New `Shell/Dashboard/`. **`DashboardGrid`** — the fixed **6 × 4** cell grid; the *shell* owns the `ComponentSize` → cell footprint (`.compact` 2×1 / `.medium` 3×2 / `.large` 6×2 / `.full` = whole grid, not a widget); `GridPoint` / `GridSpan` / `GridRect` (half-open rect + `intersects`) + `contains(_:)`, all pure. **`DashboardLayout`** — SDK-neutral `Codable`: ordered `[DashboardPage]` → ordered `[WidgetPlacement]` = `{ id: UUID, featureID, size, origin: GridPoint }`; placement identity is in `Equatable` and round-trips; `page(at:)` bounds-checked; `DashboardLayout.starter(featureID:)` builds the seed. **`DashboardLayoutValidator`** — pure enum namespace, **not** owned by the store: `validate(_:grid:)` (duplicate id / non-widget size / out-of-bounds / per-page overlap) + `@MainActor validate(_:grid:registry:)` (unknown feature / unsupported size); `DashboardLayoutIssue`. **`DashboardLayoutStore`** — `@MainActor ObservableObject`; persists a private `{ version: Int, layout }` JSON envelope under **`shell.dashboardLayout.v1`** in `UserDefaults`; `init` returns the persisted layout only if it exists, decodes, `version == schemaVersion` (**1**), *and* passes the structural validator — else the injected **seed**; `replace(with:)` / `resetToDefault()` are the (unused-in-M5.2.0) save path; first run persists nothing. **`DashboardSpaceView`** replaces `DashboardPlaceholderView`: reads the store, resolves `featureID` via `FeatureRegistry` → `DashFeature.makeComponentView(size:)` (a labelled placeholder for Maps until M5.2.1), absolute-positions each widget on the grid from a `GeometryReader`, prev/next + page dots when `pageCount > 1`; unknown feature / unsupported size / `.full` → `UnresolvedWidgetView`; `resolvedPageIndex` clamps the shell's requested page. **`DashApp`** seeds `DashboardLayoutStore` with `DashboardLayout.starter(featureID: MapFeature.id)` — a **two-page Maps-only** layout (page 1: `.large` (0,0) + `.medium` (0,2) + `.compact` (3,2); page 2: `.large` (0,0) + `.medium` (0,2)) proving multi-size / multi-position / multi-page; a test validates it clean against the real registry. **`DashboardShell`** gains only `@EnvironmentObject layoutStore` + a `DashboardGrid` constant + the `.dashboard(page:)` → `DashboardSpaceView` wiring (page nav is `ShellSurface.dashboard(page:)` + `ShellStore.goToPage`, both since M5.0); it still references no Map view model. `MapFeature` unchanged. Tests: new **`DashboardLayoutTests` (16)** + **`DashboardLayoutStoreTests` (8)** — model / grid / validator (structural + registry-aware), Codable round-trip incl. identity, default seeding, persistence round-trip, corrupt / wrong-version / structurally-invalid → seed fallback, `resetToDefault`, `DashboardSpaceView` page clamp. Build clean (app), no source warnings; full suite **347/347** (`xcodebuild test -scheme Dash`, iPad iOS 26.5 sim). **Device-verified on the physical iPad** — the dashboard page renders the placeholder widgets on the grid and page navigation works. §5 item 34. |
| `e8e913f` | **Dashboard "M5.1": app-scoped Map runtime state** (2026-09-03) (ownership / lifecycle only — **no** routing / navigation algorithm change, no new features, no Map UX change). The five Map view models (`MapViewModel` / `DestinationStore` / `PlaceSearchViewModel` / `RouteViewModel` / `NavigationViewModel`) moved from `@StateObject`s inside `ContentView` onto **`MapFeature`**, which the `FeatureRegistry` holds for the app's lifetime. `ContentView` → **`MapFullScreenView`** (moved into `Features/Map/`), which now only *observes* those instances (`@ObservedObject` fed from `MapFeature` in `init`); the `.task { searchVM.onDestinationChosen = … }` wiring moved to `MapFeature.init` (`[weak self]`). Result: **Maps → Home → Maps no longer resets an active route / navigation session.** `makeFullScreenView()` returns a **cached** `AnyView(MapFullScreenView)` so an unrelated `DashboardShell` `body` re-render can't rebuild the map under a live session; leaving Maps entirely still tears the `GMSMapView` down and rebuilds it on return from the persisted state. The `LocationStore` fix pump + the M4.6 off-route → auto-reroute chain still live in `MapFullScreenView` and run while it is on screen. Tests: new **`MapFeatureTests` (6)** — manifest; the feature owns its view models for its lifetime; presenting `MapFullScreenView` observes the feature's instances (not new ones); an active navigation session is not recreated by re-presenting Maps; injectable VMs; the search → `DestinationStore` wiring persists. `DashTests` **320/320**, build clean, device-verified. §5 item 33. |
| `258ffde` | **Dashboard "M5.0": CarPlay-style shell / feature seam** (2026-09-03) (the shell/feature boundary only — no dashboard grid, no customization, no Speedometer / Music / `ThemeManager`, no Map internal refactor, no landscape lock, no battery/network status). New **`Features/`**: `DashFeature` protocol + `FeatureID` (= `String`) + `FeatureManifest` (id / title / symbolName / supportedSizes / defaultSize); **`ComponentSize`** (compact / medium / large / full; `widgetSizes` / `isWidget`); **`FeatureRegistry`** (`@MainActor ObservableObject`; ordered `[any DashFeature]` + `feature(_:)` lookup + `duplicateIDs(in:)` with a `precondition` on init; **`FeatureRegistry.makeDefault()` is the one place the feature set is declared** — `[MapFeature()]`). New **`Shell/`**: `ShellSurface` (`home(page)` / `dashboard(page)` / `app(FeatureID)`, `Codable`); `ShellStore` (`@MainActor`; `surface` / `sidebarCollapsed` / `returnSurface`; `showHome` / `showDashboard` / `goToPage` / `openApp` / `closeApp` / `toggleSidebar` — pure, feature-agnostic; `openApp`→`closeApp` returns to the prior space surface); **`DashboardShell`** (the single layout owner) = persistent **`SidebarView`** (Home / Dashboard / one button per registered feature; **`ConnectedControlView` moved here** from the old `RootView` overlay) + content switching on `ShellSurface`; **`HomePlaceholderView`** (a tile per registered feature + "coming soon" tiles); a `DashboardPlaceholderView`. **`MapFeature`** — the ONLY bridge between `Shell/` and Map code — wraps the existing `ContentView` full-screen. **`RootView`** now shows `DashboardShell` (not the map) when connected; the connection gate + `ConnectionSetupView` are untouched. `DashApp` builds + injects `FeatureRegistry.makeDefault()`. Tests: new **`ComponentSizeTests` (3)** + **`ShellStoreTests`** (`ShellSurface` + `ShellStore` navigation, incl. openApp→closeApp round-trip) + **`FeatureRegistryTests`** (lookup / order / duplicate-id detection / default registry registers Map) + **`MapFeatureTests`** (manifest) — +23 total. `DashTests` **~316**, build clean, device-verified. §5 item 33. |
| `73879e7` | **Map "M4.6": smart off-route detection + automatic rerouting** (2026-09-02; **refined 2026-09-03 after a physical drive**) (detection + auto-reroute only — **no** traffic-aware routing, traffic colours, continuous polling, voice guidance, or dashboard work). New pure **`OffRouteDetector`** (`Routing/`, reuses `RouteGeometry.project`): `record(position:on:)` → `onRoute` / `possiblyOffRoute` / `confirmedOffRoute` behind named conservative thresholds — **`onRouteToleranceMeters` 20 / `offRouteThresholdMeters` 35** hysteresis band **/ `confirmationFixCount` 3** *consecutive meaningful* off-route fixes (one or two noisy fixes never trigger) / `resignalAfterFixes` 8 (tightened from 40 / 70 / 4 — the original felt too slow in the car) — signalling **once per episode**; rejoining ends the episode and re-arms. **`NavigationViewModel`** owns the detector (fed from the existing `update(with:)` fix pump), exposes `offRouteStatus` + `needsAutomaticReroute` (+ `clearRerouteRequest()`), and re-arms it on `start` / `reroute` / `stop`. **`RouteViewModel.autoReroute(from:now:)`** runs through the **same `refresh` field + `refreshTask`** as the M4.5 manual Refresh (never concurrent, never doubled), flagged **`@Published refreshWasAutomatic`**; derived **`isRecalculating` / `isAutomaticallyRecalculating`** flip *synchronously* when the request starts (before the API responds) so the "Recalculating…" pill is visible for the whole request and SwiftUI re-renders on the transition. `canAutoReroute(now:)` gates it on a destination + nothing refreshing + `autoRerouteCooldownSeconds` (25, from the last automatic run's *completion*); the manual Refresh ignores the cooldown and cancels an in-flight auto run; a new destination clears the cooldown. **`ContentView`**: after `navVM.update`, `needsAutomaticReroute` → `clearRerouteRequest()` + `autoReroute(from: currentOrigin)`; on `refresh == .options` with `refreshWasAutomatic`, `adoptAutomaticReroute` = `navVM.reroute` + `mapVM.setRouteOptions` + `selectRouteOption(recommended)` + `setNavigationProgress` + `clearRefresh` — recommended route adopted, progress re-seeded, destination / mode / vehicle / follow / guidance / ETA / route-clip untouched, alternatives kept in `mapVM.routeOptions`; on failure nothing is touched. A small non-blocking **"Recalculating…"** pill (snap-in transition) under the maneuver card; a failed auto-reroute → "Couldn't recalculate — keeping current route". **No `RouteService` / `GoogleRouteService` change.** Tests: **`OffRouteTests` (38)** — detector classification / hysteresis / re-signal / re-arm / the refined thresholds / two-fixes-don't-trigger, `autoReroute` (current origin, success/failure, cooldown, no-concurrency w/ manual, manual-wins), the loading-state transition (synchronous, observable, manual≠automatic, failure copy), `NavigationViewModel` off-route signal, adoption sequence. Build clean (app), no source warnings; full `DashTests` green (**293/293** per `xcresulttool`). Not yet device-verified (a live missed-turn drive is pending). §5 item 32. |
| `678e478` | **Map "M4.5": multiple route options + manual route refresh** (selection + refresh only — **no** traffic-aware routing, traffic-coloured polylines, polling, off-route detection, automatic rerouting, voice, or dashboard work). **`RouteService.routes(from:to:) → [Route]`** — `GoogleRouteService` adds `computeAlternativeRoutes: true` (still `TRAFFIC_UNAWARE`), `parseRoutes` maps every route in response order keyed `"route-<index>"`, dropping unusable ones; Google DTOs stay in-file; `Route` gains a stable `id`. New SDK-neutral **`RouteOptions`** (routes + `selectedID` + `summaries` with a "Recommended / N min faster / N min longer / Similar time" label). `RouteViewModel.state` carries `loaded(RouteOptions)`; a **separate `refresh` field** (`none` / `recalculating` / `options` / `noCurrentLocation` / `failed`) drives a manual **Refresh Route** from the *current* location + remembered destination without disturbing the active route. **`MapViewModel` owns selection + rendering**: `setRouteOptions` / `selectRouteOption` pick the active `route`; `rebuildRoutePolylines` draws the selected route `.selected` (clipped while navigating) + the rest `.alternative` with stable ids (no stale line); preview select re-fits the camera and **does not start navigation**; nav-refresh adopt swaps the route + resets `navigationProgress` + keeps the vehicle indicator + doesn't restart the session + only moves the camera if follow is on. **`MapEvent.tappedRoute(id:)`** picks an alternative from the map (preview only). **`NavigationViewModel.reroute(to:from:)`** re-seeds progress mid-drive. `MapPolyline` gains `role`; `GoogleMapProvider.syncPolylines` styles by role (`.selected` thick blue z2 / `.alternative` thin grey z1), makes lines tappable, and emits `.tappedRoute`. **`RouteOptionsPanelView`** — a compact chip row (preview selector + nav-refresh selector). No automatic switching on time savings. Tests: new **`RouteOptionsTests` (8)** + `RouteTests` / `NavigationTests` M4.5 cases (+27 total). Build clean (app + device), no warnings; full `DashTests` green (258). Physically verified on the iPad. §5 item 31. |
| `4697557` | **Map "M4.4": route info & ETA** (display only — **no** new route data, traffic-aware routing, rerouting, off-route detection, alternatives, voice, or dashboard work). A bottom **`RouteInfoPanelView`** shows distance · travel time · arrival time: over the route preview it's the whole-route figures with ETA = now + `Route.duration`; during navigation it swaps to remaining distance (from `NavigationProgress`) · remaining time (**new `NavigationProgress.remainingDuration(along:)` — `route.duration` × distance-fraction-left, no traffic model**) · ETA = now + that. Formatting is pure + SDK-neutral: **`RouteFormat`** (`distance` / `duration`) + **`Duration.inSeconds`** in `Routing/`; the ETA clock string uses **`Date.FormatStyle` with the viewer's locale + time zone** (both injectable for tests — no hardcoded format). **`RouteInfo`** (`.preview(route:)` / `.remaining(route:progress:)`, `Kind` carrying distinct labels) builds the model from the existing `Route` + `NavigationProgress` — no duplicate route maths. **`NavigationViewModel.routeInfo(now:)`** exposes the live info (`nil` inactive / arrived). `ContentView` shows the panel in a bottom `TimelineView(.periodic(by: 30))` (so a stationary preview ETA still ticks; nav also refreshes per fix), above the Start button; the preview panel is plain material ("Distance / Time / Arrival"), the live one blue-accented ("Remaining / Time left / ETA"). Maneuver card / Start button / camera **untouched**. Tests: new **`RouteInfoTests` (17)**. Build clean (app + device), no warnings. **Device-verified** (preview panel, swap to live panel on Start, figures updating with movement). **Polish pass (same working tree):** (1) `MapCameraPlan.navigation` gains `vehicleVerticalAnchor` — the vehicle sits *slightly below* centre (was pushed above; `GoogleMapProvider` turns the anchor into top viewport padding); (2) during navigation the drawn route line is clipped to the road still ahead (`RouteGeometry.remainingPolyline` off `route.polyline` + the M4.3 projection — `Route` never mutated), full route in preview / cruising, cleared on arrival / End; (3) in preview the info panel + Start button share one bottom row (panel flexible/larger, button hugging right). Start / maneuver-card / follow-recenter / user-pan behaviour and `RouteInfo` content unchanged. Tests: +12 (`NavigationTests` `remainingPolyline` + `RemainingRouteRenderTests` + camera-anchor). Full `DashTests` green (231). Installed on the iPad; polish visual check pending. §5 item 30. |
| `a262a9c` | **Map "M4.3": start navigation & maneuver guidance** (guidance display + camera only — **no** off-route detection, rerouting, alternative routes, traffic switching, voice, lane guidance, ETA, or dashboard work). `Route` gained **`steps: [RouteStep]`** (SDK-neutral `ManeuverType` + instruction + road name + point + step polyline + distance; defaults `[]`). `GoogleRouteService`: field mask adds `routes.legs.steps.*`, private DTOs + the Google `Maneuver` → `ManeuverType` table + an "onto/on/toward" road-name heuristic all stay in-file (step fields = Routes **Advanced** SKU, still free-tier once-per-trip). New pure engine in `Routing/`: **`RouteGeometry`** (haversine / polyline length / point→polyline projection) and **`NavigationProgressCalculator`** — progress is one monotone `traveledMeters` scalar; a fix advances the displayed maneuver **by ≤ 1** and a fix > ~80 m off every step is ignored, so noise never skips a turn. **`NavigationViewModel`** (`@MainActor`, mirrors `RouteViewModel`; `inactive` / `navigating(NavigationProgress)` / `arrived`) builds a **`ManeuverCard`**. **`ManeuverCardView`** (top-of-map, CarPlay-style: arrow + big distance + instruction/road + End) and **`StartNavigationButton`** are presentational; `ContentView` swaps the search + route-status overlay for the card while navigating and wires the fix pump → `navVM.update` → `mapVM.setNavigationProgress`. **`MapViewModel.startNavigation()`** (gated on route + a fix + preview mode) enters `.navigating`; the follow camera keeps M4.2's tilt/below-centre framing and overrides the zoom via pure **`navigationZoom(...)`** — base until ~350 m from a `warrantsCloserView` maneuver, ramping to `+1.5` by ~40 m, **quantised to 0.5 steps**, easing back after; follow-off freezes it; recenter restores nav follow. **No `GoogleMapProvider` change.** Tests: new **`NavigationTests` (+~33)** + `RouteTests` (+4). Build clean (app + device), no warnings; full `DashTests` green (202 / 202). **Physically verified on the iPad** — Start Navigation, maneuver card + live updates, route progress, navigation follow / recenter, dynamic maneuver zoom all work. §5 item 29. |
| `d8b291e` | **Map "M4.2": camera follow, manual pan/zoom & recenter** (camera framing only — **no** turn-by-turn, maneuvers, ETA, rerouting, voice, navigation UI, or dashboard work). New `@Published MapViewModel.followsVehicle` (on by default): in `.cruising` / `.navigating`, `update(with:)` re-derives the rendered camera each fix only while follow is on; otherwise the `VehicleIndicator` moves under a fixed camera. **`.destinationPreview` is untouched** — still a one-shot `.fit`, no re-frame on a fix, and a pan there does not drop follow. New `recenter()` / `showsRecenterButton`; `setMode` / `setDestination` re-arm follow. New **`MapCameraPlan.navigation(state, pitchDegrees:, focusBelowCentre:)`** — tilted, vehicle-below-centre framing for `.navigating` (constants on `MapViewModel`: pitch 55°, focus 0.28). `GoogleMapProvider`: user-gesture vs programmatic split lives here — `MapEvent.cameraIdle(_, byUserGesture:)` is `true` for **any** user pan/zoom/rotate (no distance/zoom threshold) and `false` for programmatic moves, via a pure `UserGestureLatch` over GMS `willMove(byGesture:)` (latched so a follow animation firing mid-gesture can't mask it); `.navigation` sets `viewingAngle` + bottom `mapView.padding`. New presentational **`RecenterButton`** (SwiftUI, **not** in `GoogleMapProvider`), overlaid by `DashMapView` when `showsRecenterButton`. Tests: **`CameraFollowTests` (20)** + `MapContentTests` (2 renamed/expanded). Build clean, no warnings; `DashTests` green. **Device-verified** (cruising follow, any-size pan/zoom drops follow + shows recenter, recenter restores). *(The first pass used an `isMeaningfulMove` distance threshold; device testing showed small/fast gestures slipping through, so gesture detection was simplified to trust `willMove(byGesture:)` alone.)* §5 item 28. |
| `8255749` | **Map "M4.1": current-location / vehicle indicator** (indicator only — **no** follow camera, navigation camera, ahead-of-vehicle framing, recenter, heading smoothing, or dashboard work). New SDK-neutral **`VehicleIndicator`** (`coordinate` + `headingDegrees: Double?`; `init(_ packet:)` validates the heading — negative / NaN → `nil`). `MapContent.vehicle` changes from `MapCoordinate` → `VehicleIndicator`; `MapViewModel.update(with:)` sets it from the latest `LocationPacket` (position + validated heading); `cameraPlan()` reads `.coordinate` — **camera logic byte-for-byte unchanged from M1**. `GoogleMapProvider`: the one vehicle `GMSMarker` is now `isFlat`, centre-anchored, `zIndex 1`, not tappable; **`vehicleStyle(for:)`** (pure `nonisolated static`, no GMS, unit-tested) → `.locationDot` / `.directionalPointer(rotationDegrees:)`; `syncVehicle(_:on:)` swaps a code-drawn **blue dot** (no heading) / **blue arrowhead** (heading) icon and sets `marker.rotation` = bearing. No `LocationPacket` / `LocationTracker` / relay change — heading was already on the wire. Tests: new **`VehicleIndicatorTests` (9)** + `MapContentTests` +3. Build clean, no warnings; full `DashTests` green (145). **Device-verified** (blue dot / rotating pointer, distinct from the red pin + blue route). §5 item 27. |
| `28b5be5` | **Map "M3": routing** (routing only — no turn-by-turn, maneuvers, navigation / ahead-of-vehicle camera, vehicle heading/arrow, auto-rerouting, voice, or dashboard work). New `Features/Map/Routing/`: SDK-neutral **`RouteService`** protocol + `Route` (`polyline` / `distanceMeters` / `Duration`) + `RouteError`; **`GoogleRouteService`** — Google **Routes API** over `URLSession` (`Foundation` only, no GMS types; `TRAFFIC_UNAWARE` DRIVE `computeRoutes`, minimal field mask), transport + key accessor injected for tests; `GooglePolyline.decode` (pure encoded-polyline decoder); `RouteViewModel` (SDK-free, holds no `LocationStore`; `state` = `idle` / `loading` / `loaded(Route)` / `noCurrentLocation` / `failed`; one request per selection or Retry, cancels in-flight, **no auto-reroute**); `RouteStatusView` (small transient `.regularMaterial` pill: spinner / "Waiting for GPS" / "Route unavailable" + Retry — **not** a nav sheet, no ETA). `MapViewModel.setRoute(_ route: Route?)` puts one `MapPolyline(id: "route", …)` on `MapContent.polylines`, and — **only in `.destinationPreview`** — re-fits the `.fit` camera **once** around vehicle + destination + route so the whole route is visible (a later fix still does not move it — not navigation camera); `.cruising` camera untouched; `setDestination(_:)` clears the stale route. `GoogleMapProvider` **unchanged** — its M1 `GMSPolyline` sync path draws the route. `GoogleMapsConfiguration.apiKey` / `.infoPlistKey` marked `nonisolated` (plain `Bundle.main` read; no behaviour change). `ContentView` wires `destination → setDestination + requestRoute`, `routeVM.state(.loaded) → setRoute`. Also carries the **`X-Ios-Bundle-Identifier` header** (added during device verification — the key's iOS app restriction was 403-blocking the raw REST call). Tests: new **`RouteTests` (29)**. Build clean, no warnings. **Device-verified on the iPad:** live `computeRoutes` request succeeds, blue polyline draws, preview camera frames it — Routes API confirmed enabled + authorised (§3). §5 item 26. |
| `973ffc9` | **Map "M2": destination search** (search + destination selection only — no routing, navigation, or Apple Maps; dashboard / connection / relay untouched). Adds the **Google Places SDK** (`GooglePlaces` product, `ios-places-sdk` SPM, up-to-next-major from 11.1.0, Dash target only). New **`PlaceSearchService`** protocol — deliberately separate from `MapProvider` — with `GooglePlaceSearchService` (the only new `import GooglePlaces` file besides `GooglePlacesConfiguration`): autocomplete + Place Details (New) + one lazy `GMSAutocompleteSessionToken` per run, GMS errors mapped to `PlaceSearchError`. SDK-free: `Destination` / `PlaceSuggestion`, `DestinationStore` (source of truth for the chosen `Destination?`), `PlaceSearchViewModel` (debounce → suggestions → `resolve` → `onDestinationChosen`), custom `MapSearchView` (field + list + selected-destination chip). `MapViewModel.setDestination(_:)` drops a `MapMarker`, frames vehicle + destination via `MapCameraPlan.fit`, and toggles `.destinationPreview` ⟷ `.cruising`. `ContentView` composes map + search + store (none reference each other). `GooglePlacesConfiguration.bootstrap()` reuses the Maps key. Also in this commit: the M1 rendering-boundary widening (row below), and a follow-up `MapSearchView` styling fix — the suggestion-row secondary line + distance were invisible (`.foregroundStyle(.secondary)` / `.tertiary` wash out over `.regularMaterial`), changed to `Color(uiColor: .systemGray)`. Tests: new `PlaceSearchTests`, `MapContentTests` +M2 cases. Build clean; full `DashTests` green. **"Places API (New)" is enabled; autocomplete + the suggestion list are device-verified (§3). Place Details resolve / pin / preview camera still device-unverified (§6).** §5 item 25. |
| `973ffc9` | **Map "M1": widen the rendering boundary** (committed together with M2, above — architecture only — no new SDKs/APIs, no search/routing/navigation/Apple Maps, no dashboard/connection changes; existing behaviour preserved). `MapProvider` goes from `makeMapView(camera:)` to `makeMapView(content: MapContent, onEvent:)` — SDK-neutral render state in, `MapEvent` out — and is kept **rendering-only** (search/routing become separate service abstractions later). New small SDK-neutral types: `MapGeometry` (`MapCoordinate`, `MapCoordinateBounds`), `MapCameraPlan` (`.follow` / `.fit`), `MapContent` (camera / vehicle / polylines / markers), `MapOverlay` (`MapPolyline`, `MapMarker`), `MapEvent` (+ `MapPOI`, `MapCameraPosition`), `MapMode`. `MapViewModel` gains `mode` / `setMode` / `handle(_:)` (no-op seam) and assembles `MapContent`. `GoogleMapProvider` becomes a `GMSMapViewDelegate` with `MapContent` diffing + keyed overlay dicts; still the only `import GoogleMaps` Map file. Fixed the two pre-existing `MapViewModel` main-actor warnings. Tests: new `MapContentTests` (10 — `MapCoordinateBounds` math + `MapViewModel` content/mode); existing `MapCameraStateTests` / `MapViewModelTests` unchanged and green. Build clean; full `DashTests` green (82). §5 item 24. |
| `c3a3a18` | **physical-device discovery fix + connection UX refinement.** Discovery fix: `LocationReceiver`'s `NWBrowser` now uses `.bonjourWithTXTRecord(type:domain:)` instead of PTR-only `.bonjour(...)` — on device the plain descriptor delivered every result with `metadata == .none`, so the identity TXT never reached Dash (first-time pair now works iPhone↔iPad over Personal Hotspot). Testable seam `LocationReceiver.txtEntries(from:)` + `LocationReceiverTests` (7, incl. nil-metadata). UX (§5 decision 23): "Disconnect" while searching → **"Stop Searching"**; new `ConnectedControlView` overlay gives **Disconnect / Forget `<name>`** while connected (attached in `RootView`, not `ContentView`); DashRelay `.waiting` gains **"Stop Sharing"**; `pairAndConnect(to:named:)` stores a user-typed friendly name (**stable `id` untouched**) from a "Name this iPhone" alert, surfaced via `pairedRelayDisplayName`. (The temporary `[DISCOVERY-DIAG]` `os.Logger` lines used during this hardware debugging were removed before commit — none are in the source.) Tests: `ConnectionCoordinatorTests`, `ConnectionSetupViewTests`, new `ConnectedControlViewTests`, `RelayStatusViewTests`. All green. |
| `c3a3a18` | **first real Dash ↔ DashRelay pairing flow** — `DashShared` gains `RelayAdvertisement` (Bonjour TXT-record contract: stable `rid` + `name`). DashRelay: `RelayIdentity` mints/persists a per-install UUID; `LocationBroadcaster` publishes it in the service's TXT record (service name falls back to `"DashRelay"`). Dash: `LocationReceiver` reads each result's TXT record, reports the visible set via `onDiscoveryChange → [DiscoveredRelay]`, and connects **only** to the relay named by `setTargetRelay(id:)` — reconnecting only to that id, never "results.first". `KnownRelay` re-keyed to the stable id; `KnownDeviceStore` gains `pairedRelay`. `ConnectionCoordinator` now holds an injected `KnownDeviceStoring`, adds `discoveredRelays` / `connectedRelayID` / `connectedDisplayName` / `offerableRelays` / `pairedRelayName` and `pairAndConnect(to:)` / `forgetPairedRelay()`; auto-connects only to a *known* relay, never a stranger; Disconnect keeps the pairing, Forget removes it and returns to first-time browsing. `ConnectionSetupView` becomes a `Model`-driven picker + "Looking for `<name>`…" + a plain "Forget this iPhone" button. New/expanded tests: `RelayAdvertisementTests` (4), `RelayIdentityTests` (4), `LocationBroadcasterTests` (+2), `ConnectionCoordinatorTests` (18), `KnownDeviceStoreTests` (7, adapted), `ConnectionSetupViewTests` (8). All suites green (DashShared 8, DashRelay 31, Dash 63). **Pairing not yet verified device-to-device.** Device-identity rationale recorded in §5 decision 19. |
| `ec4d4a9` | **first DashRelay connection/status UI** — `RelayStatusScreen` (container, reads `RelaySessionController`) + `RelayStatusView` (presentational, `State` + `onStart`/`onDisconnect` closures) in a new `DashRelay/Features/Status/` folder. Startup/waiting screen (`stopped` → Start; `waiting` → "Ready to Connect" + spinner) and a connected screen (`connected` → Disconnect, wired to the existing `RelaySessionController.stop()`). Connected screen shows a **generic** message — no device name, because the session layer does not expose a client name. `DashRelayApp` root swapped to `RelayStatusScreen`; `DashRelay/ContentView.swift` scaffold removed. New `RelayStatusViewTests` (5). `waiting` state rendered on the iPhone simulator, portrait + landscape. No pairing controls. |
| `9ccf6e0` | **feat(connection): add setup screen** — first Dash connection/setup UI. `ConnectionSetupView` in `Dash/Features/Connection/`: shown by `RootView` whenever Dash is not connected; communicates *not connected / discovering / connecting* and that a DashRelay iPhone on the same Wi‑Fi is needed; offers **Disconnect** while discovering/connecting and **Search for DashRelay** while idle; no pairing controls. Presentational (`ConnectionState` + closures in, `ConnectionSetupView.Display` for the mapping). `RootView` gate: `ContentView` ⟺ `isConnected` else `ConnectionSetupView`. New `ConnectionSetupViewTests` (5). Rendered on iPad portrait + landscape and iPhone portrait in the simulator. DashRelay UI untouched. |
| `9a02364` | **feat(connection): add session and pairing foundation** — iPad `ConnectionCoordinator` (`disconnected`/`discovering`/`connecting`/`connected`, `startSession()`/`disconnect()`, feeds `LocationStore`) + `RootView` gate; iPhone `RelaySessionController` (`stopped`/`waiting`/`connected`, `start()`/`stop()` controls GPS); `KnownDeviceStore` for pairing state (storage only). `LocationStore` narrowed to location data + watchdog (lost `linkPhase`). `LocationReceiver.Status` gains `connectedServiceName`; `LocationTracker` gains a `wantsTracking` gate. New: `ConnectionCoordinatorTests` (12), `KnownDeviceStoreTests` (7), `RelaySessionControllerTests` (8). Deliberate disconnect verified (unit) not to auto-reconnect and to stop GPS; gate verified in the simulator against a real relay. |
| `b3c98cb` | **docs: add project status** — this document. |
| `54fa7e8` | **feat(map): add live vehicle map** — bootstrap Google Maps in `DashApp`; `ContentView` shows a full-screen `DashMapView` fed from `LocationStore.latestPacket`; `GoogleMapProvider` gains a vehicle `GMSMarker` that follows the camera. Verified in the simulator (SDK 11.1.0 initialises, map + marker render). |
| `61eb89a` | **feat(map): add map provider abstraction** — added the Google Maps SPM dependency (pinned 11.1.0, Dash target only) and the secure API-key config (xcconfig → Info.plist → `GoogleMapsConfiguration`); created `MapProvider` / `MapProviderID` / `MapCameraState` / `MapViewModel` / `DashMapView` / `GoogleMapProvider`; `MapCameraStateTests`. |
| `4362d0a` | **feat(dash): wire location store into app** — `DashApp` owns `LocationStore` as `@StateObject`, injects it as `environmentObject`, starts it in `.task`. |
| `8d44544` | **feat(dash): add location store and watchdog** — `LocationStore` single source of truth + `Task`-based staleness watchdog; connected to `LocationReceiver`; `LocationStoreTests`. |
| `133a79a` | **feat(dash): add Bonjour location receiver** — `LocationReceiver` (`NWBrowser`/`NWConnection` + reconnect) and `PacketLineBuffer`; moved shared framing into `DashShared.LocationWireFormat`; `LocationReceiverTests`, `PacketLineBufferTests`. |
| `0a7dbfb` | **feat(relay): add network broadcaster** — `LocationBroadcaster` (`NWListener` + Bonjour, multi-client, `\n`-delimited JSON); `DashRelayApp` wires tracker → broadcaster; DashRelay Bonjour Info.plist keys; `LocationBroadcasterTests`. |
| `b6e5938` | **feat(relay): add location tracking** — `LocationTracker` wraps `CLLocationManager`, converts fixes to `LocationPacket`; DashRelay background-location Info.plist / capability; `DashShared` linked to DashRelay; `LocationTrackerTests`. |
| `4b89dcf` | **add LocationPacket** — `DashShared` package with the `Codable` `LocationPacket` wire model; `LocationPacketTests`. |
| `a983769` | **docs: add project specification** — `PROJECT_SPEC.pdf`. |
| `80c4c7f` | **docs: add Claude Code project instructions** — `CLAUDE.md`. |
| `296e280` / `6fde0a9` | Initial Xcode project / initial commit. |

### Verified milestones (beyond automated tests)

- **iPhone → iPad location transfer over Bonjour/TCP** — confirmed on physical
  devices by the developer (manual, pre-dates this repo's automated suite).
- **Google Maps renders in Dash** — confirmed in the iOS Simulator (map tiles +
  vehicle marker, SDK authenticated with the configured key). **Predates the M1
  `GoogleMapProvider` rewrite** — the delegate/diffing rewrite builds clean but
  has not been re-run on a simulator/device.
- **Connection gate reaches `.connected` against a real relay** — confirmed in
  the iOS Simulator: Dash discovered a live DashRelay on the LAN, ran
  `discovering → connecting → connected`, and `RootView` swapped to the dashboard.
  The deliberate-disconnect and no-auto-reconnect behaviour is covered by unit
  tests only, not this manual check.
- **The dashboard is gated behind an active connection** — with no relay on the
  LAN, `RootView` shows `ConnectionSetupView` (not the map), rendered in the
  `discovering` state on iPad **portrait and landscape** and on iPhone portrait
  in the iOS Simulator.
- **DashRelay status screen renders** — the DashRelay app launched in the iOS
  Simulator shows `RelayStatusView` in the `waiting` state ("Ready to Connect" +
  spinner) in both portrait and landscape. `stopped` / `connected` are covered by
  unit tests only.
- **Pairing flow — first-time pair verified on hardware, the rest automated only.**
  Discover-then-pick + connect works iPhone↔iPad over the Personal Hotspot (§3).
  Auto-prefer-paired on a later launch, "Looking for `<name>`…", Disconnect,
  Forget, "Stop Searching", the "name this iPhone" prompt, and
  `ConnectedControlView` are covered by the Swift Testing suites only.
- **Map M1 — automated only.** The M1 `GoogleMapProvider` delegate/diffing rewrite
  is covered by SDK-neutral Swift Testing suites + a clean build; not re-run on a
  device or simulator since the pre-M1 "map + vehicle marker renders" check.
- **Map M2 — autocomplete verified on device.** On the physical iPad,
  `GooglePlaceSearchService` autocomplete against the live **Places API (New)**
  returns real results and the `MapSearchView` suggestion list renders (a contrast
  bug in the row styling was found and fixed — §3, §6). Not yet run on device:
  choosing a suggestion (Place Details resolve), the destination pin, and the
  `.destinationPreview` camera.
- **Map M3 — device-verified.** On the physical iPad, selecting a destination
  fired a real `computeRoutes` request, the route came back, and the **blue
  polyline drew** with the preview camera framing it. Needed the
  `X-Ios-Bundle-Identifier` header — the key's iOS application restriction was
  returning `API_KEY_IOS_APP_BLOCKED` (403) on the raw REST call because,
  unlike the Maps / Places SDKs, `URLSession` was not sending the bundle id.
  The Routes API is confirmed **enabled + authorised** on the project. Diagnosed
  with a temporary `NSLog` that logged the 403 body (since removed). Committed
  `28b5be5`.
- **Map M4.1 — device-verified.** On the physical iPad the blue dot / rotating
  pointer rendered, followed `LocationPacket.heading`, moved with new fixes, and
  read as visually distinct from the red destination pin and the blue route line.
  +12 unit tests cover `LocationPacket` → `VehicleIndicator` (heading validation)
  and the `GoogleMapProvider.vehicleStyle` dot-vs-pointer decision. Committed
  `8255749`.
- **Map M4.2 — device-verified; committed `d8b291e`.** On the physical iPad:
  cruising follows the vehicle, any-size pan/zoom drops follow and shows the
  recenter button, GPS fixes move the vehicle under a fixed camera while follow
  is off, and recenter restores it. The first build used a distance/zoom
  threshold (`isMeaningfulMove`) that let small/fast gestures slip through on the
  iPad; it was removed (any `willMove(byGesture:)` gesture drops follow, latched
  against a mid-gesture follow animation) and re-verified. +20 `CameraFollowTests`.
- **Map M4.3 — device-verified.** Physically tested on the iPad (2026-09-02):
  the Start Navigation button appears over a loaded route preview, tapping it
  enters `.navigating` and shows the maneuver card, the card's arrow /
  instruction / distance update as the vehicle moves along the route, the
  navigation follow camera tracks with the tilt + below-centre framing, the
  dynamic maneuver zoom tightens approaching a turn and eases back after, a
  manual pan/zoom drops follow and recenter restores navigation follow, and the
  route line + vehicle indicator stay correct. +~37 unit tests (`NavigationTests`
  + `RouteTests` additions) cover the geodesic helpers, the progress engine
  (advance-by-one, ~80 m off-route rejection, arrival), the navigation view model
  + maneuver card, `MapViewModel`'s navigation camera / dynamic zoom, and the
  Google step/maneuver parsing (canned JSON). Committed `a262a9c`. Off-route
  detection / rerouting / voice remain out of scope (M4.5+).
- **Map M4.4 — route info & ETA + polish pass — device-verified; committed
  `4697557`.** On the physical iPad: the preview panel (distance / travel time /
  arrival time), the swap to the live "Remaining / Time left / ETA" panel on
  Start, figures updating with movement, the vehicle sitting a little below
  centre while navigating, the route line shortening as the drive progresses,
  and the preview bottom row in both orientations. +29 unit tests
  (`RouteInfoTests` + `RouteGeometry.remainingPolyline` + `MapViewModel` route
  clipping + camera anchor).
- **Map M4.5 — multiple route options + manual refresh — device-verified;
  committed `678e478`.** +27 unit tests: `RouteOptions` model (construction /
  selection / alternatives / summaries + relative labels), Google multi-route
  parse with stable ids, `computeAlternativeRoutes` in the request body,
  `RouteViewModel` multi-route + single-route fallback + the manual-refresh state
  machine (current origin, remembered destination, `recalculating` → `options`,
  no-location / no-destination / failure land on `refresh` only), `MapViewModel`
  selection + rendering (preview draws all + emphasises the selected + re-fits +
  does not start navigation; Start uses the selected route; a map polyline tap
  selects in preview, ignored while navigating; refresh-during-navigation offers
  without switching, adopting swaps the active route + resets progress + keeps
  the vehicle + removes the old geometry + respects follow-off),
  `NavigationViewModel.reroute`. Physically verified on the iPad.
- **Map M4.6 — smart off-route detection + automatic rerouting — automated only;
  partially driven (see refinement).** +38 unit tests (`OffRouteTests`):
  `OffRouteDetector` classification (on / possibly / confirmed), the hysteresis
  band, one noisy fix — and two — never triggering, the consecutive-fix
  confirmation, re-signalling a still-off episode, rejoin-then-re-arm, `reset()`,
  a degenerate route, **the refined thresholds** (20 / 35 / 3 asserted, ~25 m
  drift = "possibly", ~40 m deviation confirms on the third fix);
  `RouteViewModel.autoReroute` (current origin + remembered destination,
  offer-with-`refreshWasAutomatic` while `state` is untouched, failure keeps
  `state` + arms the cooldown, no destination / no fix → no request, no
  concurrent auto reroutes, refused while a manual refresh runs, a manual refresh
  interrupts an in-flight auto run, cooldown blocks until it elapses, manual
  Refresh ignores the cooldown, a new destination clears it); **the loading
  state** (`isAutomaticallyRecalculating` set synchronously before the API
  responds, `objectWillChange` fires, manual ≠ automatic, failure drops the
  loading state but keeps the failure copy, `clearRefresh` ends it);
  `NavigationViewModel` off-route signal (quiet on route, quiet on one wild fix,
  raises once on a sustained deviation, re-arm on `reroute` / `stop`, inert while
  inactive); the adoption sequence (session / mode / destination / vehicle
  preserved, progress re-seeded, alternatives kept, old geometry gone).
  **Refinement (2026-09-03) after a physical automatic-reroute test:** the
  driver reported (1) the "Recalculating…" pill was not visible during the
  request and (2) the thresholds felt too large. Fixed: `refreshWasAutomatic`
  made `@Published` + derived `isAutomaticallyRecalculating` set the instant the
  request starts (pill now snap-in, visible for the whole request), and
  thresholds tightened to 20 / 35 / 3. **Still not driven:** the tightened
  thresholds on a real missed turn; the pill on a real screen; a live
  `computeRoutes` reroute mid-drive; the recommended-route swap while following.
  Committed `73879e7`.
- **Dashboard M5.0 + M5.1 — device-verified; committed `258ffde` / `e8e913f`.**
  On the physical iPad: the CarPlay-style shell shows the sidebar (Home /
  Dashboard / Maps), Home lists the Maps tile + "coming soon" tiles, tapping
  Maps opens the full-screen map, and returning to Home then back to Maps keeps
  an active route / navigation session (M5.1's app-scoped state). Disconnect /
  Forget still work from the sidebar. +29 unit tests across `ComponentSizeTests`
  / `ShellStoreTests` / `FeatureRegistryTests` / `MapFeatureTests` cover the pure
  navigation state + the feature-ownership guarantees.
- **Dashboard M5.2.0 — the widget grid — device-verified.** On the physical
  iPad the Dashboard space renders the two-page starter layout: the placeholder
  Map widgets appear at their grid positions/sizes and the prev/next page
  controls switch pages. The layout model / grid math / validator /
  persistence (`shell.dashboardLayout.v1`, schema-version + corrupt-data
  fallback) are covered by +24 unit tests
  (`DashboardLayoutTests` / `DashboardLayoutStoreTests`). Full suite **347/347**,
  build clean. Working tree — not committed.

## M5.2.1 — Real Map Dashboard Components

Status: Implemented and physically verified.

- Added real compact, medium, and large Map dashboard components.
- Compact shows maneuver guidance while navigating instead of a tiny map.
- Medium/large render live map presentations with navigation information.
- All dashboard Map components share the app-scoped MapFeature runtime state.
- Added timestamp-deduplicated dashboard location/navigation observation.
- Existing full-screen Maps behavior remains unchanged.
- Physical test on the iPad passed; two concurrent dashboard GMSMapViews felt fine in testing.
- Full test suite: 363/363 passed.
- Build: succeeded with no new warnings.
- No commit was made by Claude.

Future requirement:
- Tapping a dashboard widget should open its corresponding feature in full-screen app mode.

Next: M5.3.0 — dashboard widget tap → full-screen feature navigation.

## M5.3.0 — Dashboard Widget Tap → Full-Screen Feature

Status: Implemented.

- Each dashboard widget is now a full-tile button; tapping it opens that widget's feature full-screen.
- `WidgetHostView` forwards only `WidgetPlacement.featureID` through a new `onOpenFeature: (FeatureID) -> Void` callback; `DashboardShell` wires it to `ShellStore.openApp` (mirroring the Home launcher).
- The dashboard layer stays feature-agnostic: `DashboardSpaceView` / `WidgetHostView` know only `WidgetPlacement`, `FeatureRegistry`, `DashFeature`, and the callback — never `ShellStore` or any feature view model.
- Close returns to the exact Home / Dashboard page the widget was opened from (existing `ShellStore.openApp`/`closeApp`/`returnSurface` semantics, unchanged).
- Full-screen path is unchanged: `FeatureRegistry.feature(id).makeFullScreenView()`, same as opening from the sidebar/Home; no Maps special-casing; app-scoped `MapFeature` state (M5.1) reused.
- Live Map widget stays non-interactive to map gestures (`GMSMapView` keeps `allowsHitTesting(false)`); the tile button handles the tap, no nested-gesture conflict. Minimal press-dim feedback, no elaborate animation.
- `MapFeature` / `MapFullScreenView` internals untouched.
- Full test suite: 370/370 passed (367 DashTests + 3 DashUITests). Build: succeeded with no new warnings.
- No commit was made by Claude.

Next: M5.4.0 — Speedometer feature (a second real `DashFeature`; sidebar + Home + dashboard widget presentations).

## M5.3.0 — Paged Home Launcher

Status: Implemented.

- Replaced the `HomePlaceholderView` grid with a real paged Home launcher (`HomeSpaceView`).
- New `HomeLayout` model: `HomeLayout` → `HomePage[]` → `HomeAppPlacement { id: UUID, featureID }`. SDK-neutral, `Codable` / `Equatable` / `Sendable`, no SwiftUI, separate from `DashboardLayout`. `pageCount` / `page(at:)` / `clampedPageIndex(_:)` / `allApps`.
- New `HomeLayoutStore` (`@MainActor`, `UserDefaults`): `{ version, layout }` JSON envelope under `shell.homeLayout.v1`, schema version 1; falls back to the seed on missing / undecodable / wrong-version / duplicate-placement-id data; stable placement UUIDs survive round trips.
- Default Home layout is derived from `FeatureRegistry` (`HomeLayout.starter(featureIDs: registry.manifests.map(\.id))`, wired in `DashApp`) — no feature-specific logic in the Home view. Maps appears as a real tile; Music / Speedometer are presentation-only "coming soon" tiles supplied by `DashboardShell` (not registered, not persisted).
- Tapping a tile forwards `HomeAppPlacement.featureID` through `onOpenFeature` → `ShellStore.openApp` → `FeatureRegistry.feature(id).makeFullScreenView()` — the same boundary and mechanism `DashboardSpaceView` uses; no Maps special-casing.
- Closing a feature opened from Home page N returns to Home page N (existing `ShellStore.openApp` / `closeApp` / `returnSurface` semantics, unchanged). Page moves are model-level (`ShellSurface.home(page:)` + `ShellStore.goToPage` + `HomeLayout.clampedPageIndex`); prev/next controls only, no swipe gesture yet.
- `HomeSpaceView` stays feature-agnostic: knows only `HomeAppPlacement`, `FeatureID`, `FeatureManifest`, and callbacks — never `ShellStore` or a feature view model.
- Sidebar, `ShellStore`, `DashboardSpaceView`, `MapFeature`, `MapFullScreenView` untouched.
- DashTests: 388/388 passed. Build: succeeded with no new warnings.
- No commit was made by Claude.

Next: M5.4.0 — Speedometer feature (a second real `DashFeature`; sidebar + Home + dashboard widget presentations).

## M5.3.1 — CarPlay-style Home + corrected space navigation

Status: Implemented.

- **One Dashboard, no Dashboard pages.** `ShellSurface` dropped `dashboard(page:)` for a single `dashboard` case; `DashboardLayout.starter` now emits exactly one page; `DashboardSpaceView` renders that page with no page controls. `DashboardLayout` keeps its page model internally for a possible future customization feature, but the product ships one Dashboard space.
- **Horizontally paged Home spaces.** The Dashboard and the Home pages form one left-to-right sequence of "spaces": `Dashboard ←→ Home page 1 ←→ Home page 2 ←→ …`. Initially just `Dashboard ←→ Home page 1`. Swiping moves between the Dashboard and Home as adjacent spaces; extra Home pages continue after Home page 1.
- **Shell-level `SpacePagerView`.** A single native `TabView` (page style) at the shell level composes `DashboardSpaceView` (tag 0) then one `HomeSpaceView` per Home page (tag N+1). Its selection is a flat "space index" (`ShellSurface.spaceIndex` / `.forSpaceIndex` / `.spaceCount(homePageCount:)`), synced two-way with `ShellStore.surface` so a swipe and a sidebar tap stay consistent. No custom gesture recognizer, no separate per-surface TabViews. A full-screen `.app` is shown by `DashboardShell` *instead of* the pager.
- **Home pages auto-generated from app count.** New pure `HomeLayout.paginate(featureIDs:capacity:)` splits the registered feature ids into pages, filling each page before starting the next — page count is exactly `ceil(count / capacity)`, minimum one, never an empty page. As real apps are added they fill page 1, then page 2, etc.
- **4×4 / 16-app launcher capacity.** `HomeGrid` (columns 4 × rows 4 = 16) is the launcher's design grid and the pagination capacity. Today: one registered app (Maps) → one Home page. The presentation-only "coming soon" tiles (Music, Speedometer) render on the last page only and are **not** counted toward pagination, so they create no extra pages.
- **Top-left app positioning.** `HomeSpaceView` lays icons out in a fixed-column grid anchored to the top-left of the usable area (sensible automotive top/left insets), filling left-to-right then top-to-bottom. The grid is not vertically or horizontally centered.
- **Home page dots only when there are multiple Home pages.** `HomePageDots` indicates Home pages exclusively (never the Dashboard), is hidden with a single Home page, and is positioned by `SpacePagerView`.
- **Preserved:** opening an app from Home page N returns to Home page N; opening a widget from the Dashboard returns to the Dashboard (`ShellStore.openApp` / `closeApp` / `returnSurface`, unchanged). The sidebar's Home / Dashboard / per-app buttons still jump directly. `HomeSpaceView` / `DashboardSpaceView` stay feature-agnostic (only `HomePage` / `WidgetPlacement` / `FeatureID` / `FeatureManifest` + callbacks); `MapFeature` untouched.
- DashTests: 401/401 passed. Build: succeeded with no new warnings.
- Physical iPad verification passed.
- No commit was made by Claude.

Next: M5.4.0 — Speedometer feature (a second real `DashFeature`; sidebar + Home + dashboard widget presentations).

## M5.3.1 — Corrected horizontal space navigation + Home launcher

Status: Implemented.

- One Dashboard space with no Dashboard pagination.
- Home automatically paginates only when registered app count exceeds capacity.
- Horizontal sequence is Dashboard ↔ Home page 0 ↔ Home page 1 ↔ ...
- Sidebar remains direct navigation.
- Home uses deterministic 4×4 top-left-first app placement.
- Home page dots appear only when multiple Home pages exist.
- Dashboard page controls/dots removed.
- Physically verified on iPad.
- DashTests: 401/401 at milestone.
- Build clean.

## M5.4.1 — Dashboard customization foundation

Status: Implemented.

- Added Dashboard edit mode owned by DashboardShell via DashboardEditModel.
- Added pure DashboardLayoutEditor transforms for add/remove/resize/move.
- DashboardLayoutStore now exposes validated mutation APIs.
- Edit mode disables normal widget activation and shows editing state.
- Layout validation remains centralized and persistence remains in DashboardLayoutStore.
- Feature-agnostic; no feature imports Shell.
- Physically verified on iPad.
- DashTests: 426/426.
- Build clean.

## M5.4.2 — Dashboard widget editing UI

Status: Implemented.

- Added custom Add Widget picker driven by FeatureRegistry manifests.
- Added automatic deterministic first-free-slot placement.
- Added edit-mode remove controls.
- Added feature-aware size selection.
- Invalid add/resize operations are rejected without corrupting persisted layout.
- Dashboard remains single-page.
- Normal widget → full-screen behavior preserved.
- Physically verified on iPad.
- DashTests: 447/447.
- Build clean.

## M5.4.3 — Dashboard drag/resize editing

Status: Implemented.

- Added grid-snapped drag-to-move with live valid/invalid ghost feedback.
- Added interactive resize through supported ComponentSize values.
- Pixel geometry isolated in DashboardGridGeometry.
- Layout mutations persist only once at interaction completion.
- Fixed physical drag jitter by using a stable global gesture coordinate space.
- Removed implicit animation fighting the live drag; animation is scoped to the ghost/settle behavior.
- Moved size menu to bottom-leading and resize handle to bottom-trailing.
- Physically tested on iPad; drag/resize now feels smooth and responsive.
- DashTests: 467/467.
- Build clean.

## M5.5.1 — CarPlay visual foundation

Status: Implemented.

- Added centralized DashTheme with dark automotive palette, typography roles, metrics, and reusable surface helpers.
- Applied theme to Dashboard, Home, Sidebar, shell chrome, widget editing UI, and widget picker.
- Established dark high-contrast surface hierarchy and restrained accent usage.
- Removed unnecessary glass/material treatment from themed shell surfaces.
- Added WCAG contrast guardrail tests.
- Dashboard/Home navigation and customization behavior unchanged.
- MapFeature/map rendering untouched.
- Physically verified on iPad and visually approved.
- DashTests: 477/477.
- Build clean.

Status update covers M5.3.1 through M5.5.1; no implementation changes made.

## M5.5.3 — Keyboard / shell movement fix

Status: Implemented. Physical iPad acceptance test PASSED.

- Symptom: focusing the Google Maps search field slid the entire rounded Dash
  shell (border, sidebar, map, wallpaper) slightly upward when the keyboard
  appeared.
- Root cause: SwiftUI's App-lifecycle keyboard avoidance inflates the root
  `_UIHostingView`'s safe-area insets when a text field becomes first responder,
  so the whole view tree is proposed a reduced layout height; the shell's
  `frame(maxHeight: .infinity)` is centre-aligned, so the shorter shell was
  re-centred — a small upward shift. SwiftUI-level `.ignoresSafeArea(.keyboard)`
  does not change what the hosting view itself reports, so it could not prevent
  this on device.
- Fix: `ShellKeyboardStability` neutralises keyboard avoidance on the root
  `_UIHostingView` directly — a runtime subclass whose `safeAreaInsets` getter
  returns the window's physical insets (never the keyboard-inflated value), plus
  no-ops of any `keyboardWill*` handlers. Applied once via
  `.stopsRootKeyboardAvoidance()` on `RootView`. Existing
  `.ignoresSafeArea(.keyboard)` at the WindowGroup root / `DashboardShell` /
  `MapFullScreenView` kept as defense-in-depth.
- No offsets, no keyboard-height calculations, no Maps-specific positioning
  hacks, no animation masking. `DashboardShell` layout and all visual styling
  unchanged.
- On device: shell, sidebar, dashboard/map, wallpaper and rounded border stay
  exactly stationary when the keyboard appears; the keyboard overlays the map
  normally; Google Maps search field, typing and suggestions work; dismissing
  the keyboard returns with no jump. Verified repeatedly.
- Temporary keyboard-geometry diagnostic logging left in place but disabled
  (`ShellDiagnostics.logKeyboardGeometry = false`).
- DashTests: 526/526. Build clean.
- Nothing committed.
