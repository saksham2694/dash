# PROJECT_STATUS.md

Living status document for **Dash**. It describes the repository as it actually
stands so a future developer (or a fresh Claude Code session) can get oriented
without conversation history.

- **Last updated:** 2026-09-02
- **Branch:** `main`
- **Latest commit:** `d8b291e feat(map): add camera follow controls` — Map
  **M4.2** (§5 item 28), physically verified on device (cruising follow, any-size
  pan/zoom drops follow, recenter restores).
- **Everything through M4.2 is committed.** Connection/pairing/relay-status →
  `9a02364` / `ec4d4a9` / `c3a3a18`; Map **M1** + **M2** → `973ffc9`; **M3** →
  `28b5be5` (Routes API device-verified; carries the `X-Ios-Bundle-Identifier`
  header); **M4.1** → `8255749`; **M4.2** → `d8b291e`. See §10 for the mapping.
- **Working tree (not yet committed):** **Map "M4.3" — start navigation &
  maneuver guidance.** `MapViewModel.startNavigation()` moves from
  `.destinationPreview` into `.navigating` (gated on a loaded route + a current
  fix), keeping the M3 route. `Route` gained `steps: [RouteStep]` (SDK-neutral
  maneuvers — type / instruction / road name / point / geometry);
  `GoogleRouteService` requests + maps the Routes API `legs[].steps[]`, Google
  maneuver vocabulary staying inside that file. A pure provider-neutral engine
  (`NavigationProgressCalculator` / `NavigationViewModel`) turns the
  `LocationStore` position + active route into the upcoming maneuver, distance to
  it, and remaining distance — advancing by at most one maneuver per fix and
  ignoring off-route noise. A CarPlay-style `ManeuverCardView` (arrow + distance
  + instruction/road) sits at the top of the map; the `.navigating` camera keeps
  the M4.2 tilt/below-centre framing and now **zooms in approaching a significant
  turn, easing back to base afterwards** (quantised, in `MapViewModel`).
  **Physically verified on the iPad** (Start Navigation, maneuver guidance, route
  progress, follow/recenter, dynamic maneuver zoom). No rerouting / off-route
  detection / alternative routes / voice / lane guidance / dashboard. See §5 item
  29, §10.
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
    │   ├── DashApp.swift            # @main; owns LocationStore + ConnectionCoordinator + KnownDeviceStore; bootstraps Google Maps + Places
    │   ├── RootView.swift           # connection gate: ContentView (+ ConnectedControlView overlay) when isConnected, else ConnectionSetupView
    │   ├── ContentView.swift        # Map-feature composition: DashMapView + MapSearchView overlay; owns MapViewModel + PlaceSearchViewModel + DestinationStore (placeholder shell, not the dashboard)
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
    │   ├── Features/Connection/
    │   │   ├── ConnectionSetupView.swift       # not-connected / setup screen: device picker + "name this iPhone" prompt, "looking for <paired>", "Stop Searching", Forget <name> (presentational)
    │   │   └── ConnectedControlView.swift      # compact overlay shown on the dashboard while connected: names the iPhone, offers Disconnect / Forget (presentational)
    │   └── Features/Map/                       # all SDK-neutral except GoogleMapProvider.swift
    │       ├── MapProvider.swift               # rendering-only protocol (MapContent in, MapEvent out) + MapProviderID
    │       ├── MapGeometry.swift               # MapCoordinate + MapCoordinateBounds (tightest-box math)
    │       ├── MapCameraState.swift            # camera value type + following(_:); MapCameraPlan (.follow / .fit / .navigation)
    │       ├── MapContent.swift                # the render state: camera plan, vehicle indicator, polylines, markers
    │       ├── VehicleIndicator.swift          # M4.1 — SDK-neutral current-location: coordinate + optional heading (from LocationPacket)
    │       ├── MapOverlay.swift                # MapPolyline + MapMarker (identified, diffable overlay descriptors)
    │       ├── MapEvent.swift                  # taps (map / POI / marker) + camera-idle (byUserGesture, M4.2-filtered); MapPOI, MapCameraPosition
    │       ├── MapMode.swift                   # cruising / destinationPreview / navigating (all realised; startNavigation() enters navigating, M4.3)
    │       ├── MapViewModel.swift              # holds provider + mode + destination + route + followsVehicle + navigationProgress; startNavigation(); dynamic nav zoom; derives MapContent; routes MapEvent
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
    │       ├── Routing/                        # M3 + M4.3 — driving route + turn-by-turn (NO SDK anywhere; GoogleRouteService is REST-only)
    │       │   ├── Route.swift                 # SDK-neutral: polyline + distanceMeters + Duration + steps [RouteStep] (M4.3)
    │       │   ├── RouteStep.swift             # M4.3 — SDK-neutral maneuver: ManeuverType + instruction + roadName + maneuverPoint + polyline + distance
    │       │   ├── RouteService.swift          # provider-neutral protocol (route(from:to:)) + RouteError
    │       │   ├── GoogleRouteService.swift    # Google Routes API over URLSession; Foundation only; maps legs[].steps[] + Google maneuver vocab (M4.3)
    │       │   ├── GooglePolyline.swift        # pure encoded-polyline decoder
    │       │   ├── RouteGeometry.swift         # M4.3 — pure geodesic: haversine distance, polyline length, project point → polyline
    │       │   ├── RouteProgress.swift         # M4.3 — pure engine: NavigationProgress + NavigationProgressCalculator (upcoming maneuver, distances, noise handling)
    │       │   ├── RouteViewModel.swift        # SDK-free: idle / loading / loaded / noCurrentLocation / failed
    │       │   └── RouteStatusView.swift       # small transient loading/error pill (presentational)
    │       └── Navigation/                     # M4.3 — active turn-by-turn session (SDK-neutral)
    │           ├── NavigationViewModel.swift   # @MainActor: start/stop/update, state = inactive/navigating(progress)/arrived, builds ManeuverCard
    │           ├── ManeuverCard.swift          # presentational model + NavigationDistance formatting
    │           ├── ManeuverCardView.swift      # top-of-map CarPlay-style maneuver card (arrow + distance + instruction/road + End) (presentational)
    │           └── StartNavigationButton.swift # "Start Navigation" action over the route preview (presentational)
    │   # (spec-planned but NOT present: Models/, Features/Music, Features/Speedometer,
    │   #  Features/Settings, Home/DashboardView, Core/ThemeManager)
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
    │   ├── RouteTests.swift                   # M3 + M4.3: Route model, polyline decode, Routes request/response mapping (incl. step/maneuver parsing), RouteViewModel, MapViewModel.setRoute
    │   ├── VehicleIndicatorTests.swift        # M4.1: LocationPacket → VehicleIndicator (heading validation); GoogleMapProvider.vehicleStyle dot/pointer
    │   ├── CameraFollowTests.swift            # M4.2: follow on/off, any user gesture disables (incl. tiny), recenter, navigation plan, UserGestureLatch
    │   ├── NavigationTests.swift              # M4.3: RouteGeometry, progress engine (advance / noise / arrival), NavigationViewModel, ManeuverCard, dynamic nav zoom
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
                                                     RootView: ContentView (+ ConnectedControlView overlay:
                                                     name / Disconnect / Forget) when isConnected,
                                                     else ConnectionSetupView(model:) — device picker +
                                                     "name this iPhone" prompt / "Looking for <paired>…" /
                                                     "Stop Searching" / "Forget <name>"
                                                        → ContentView → DashMapView → MapViewModel → GoogleMapProvider
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
- **The dashboard is gated.** `RootView` shows `ContentView` (map/dashboard) only
  when `ConnectionCoordinator.isConnected`; otherwise `ConnectionSetupView`. The
  map is never shown without an active connection. `RootView` is the only place
  that reads connection state for gating; `ContentView` and feature views never
  see it. Both connection views are presentational and hold no copy of the
  connection/pairing state:
  - `ConnectionSetupView` takes `ConnectionSetupView.Model` (state +
    `offerableRelays` + `pairedRelayName`) and closures (`onPair`, `onForget`,
    `onStopSearching`, `onSearch`). Its one bit of local state is the "name this
    iPhone" alert (presentation only).
  - `ConnectedControlView` (overlaid on `ContentView` by `RootView` while
    connected) takes the paired device name + `onDisconnect` / `onForget`
    closures. Its one bit of local state is the confirmation dialog.
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
- **[Implemented]** `RootView` — gates the UI: when connected, `ContentView`
  (dashboard) with a `ConnectedControlView` overlaid top-trailing; otherwise
  `ConnectionSetupView`. Builds the setup screen's `Model` from the coordinator
  and wires every action (`disconnect` / `startSession` /
  `pairAndConnect(to:named:)` / `forgetPairedRelay`).
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
  pill `RootView` overlays on the dashboard while connected. Shows the paired
  iPhone's friendly name (`ConnectionCoordinator.pairedRelayDisplayName`, falling
  back to "DashRelay") and, via a confirmation dialog, **Disconnect** (ends the
  session, keeps the pairing → `disconnect()`) and **Forget `<name>`** (drops the
  pairing → `forgetPairedRelay()`). Presentational; only local state is the
  dialog. Does **not** touch `ContentView` or the map. `.overlay(alignment:
  .topTrailing)` + `padding(12)` keeps it inside the safe area in both
  orientations.
- **[Implemented]** `DashApp` owns `LocationStore`, `KnownDeviceStore`, and
  `ConnectionCoordinator` (constructed with the store + known-device store) as
  `@StateObject`s, injects them as `environmentObject`s, calls
  `connection.startSession()` in `.task`, and `GoogleMapsConfiguration.bootstrap()`
  in `init()`.
- **[Implemented]** Map abstraction (widened in the "M1" pass — see §5 item 24):
  - `MapProvider` — **rendering-only** protocol: `id` +
    `makeMapView(content: MapContent, onEvent: @escaping (MapEvent) -> Void) -> AnyView`.
    No search / routing / place methods, by design.
  - `MapGeometry` — `MapCoordinate` and `MapCoordinateBounds` (`init?([MapCoordinate])`
    → tightest box; `center`).
  - `MapCameraState` — value type (lat/lon/`headingDegrees?`/zoom + `.default` +
    `following(_:)` + `center`). `MapCameraPlan` — `.follow(MapCameraState)` /
    `.fit(MapCoordinateBounds, padding:)` (route preview) /
    `.navigation(MapCameraState, pitchDegrees:, focusBelowCentre:)` (M4.2 — a
    tilted, vehicle-below-centre framing; the provider turns it into its own
    camera + viewport padding).
  - `MapContent` — the full render state: `camera: MapCameraPlan`,
    `vehicle: VehicleIndicator` (M4.1 — was a bare `MapCoordinate`),
    `polylines: [MapPolyline]`, `markers: [MapMarker]`. `Equatable` for provider-side diffing.
  - `VehicleIndicator` (M4.1) — SDK-neutral current-location: `coordinate` +
    `headingDegrees: Double?`. `init(_ packet: LocationPacket)` validates the
    heading (negative / NaN → `nil`, matching `MapCameraState.following`). Kept
    apart from `MapMarker` so a provider styles it navigation-style, not as a pin.
  - `MapOverlay` — `MapPolyline` (`id` + `coordinates`) and `MapMarker`
    (`id` + `coordinate` + `title?`), both `Identifiable`. (The vehicle indicator
    is deliberately *not* here — exactly one per render.)
  - `MapEvent` — `.tappedMap` / `.tappedPOI(MapPOI)` / `.tappedMarker(id:)` /
    `.cameraIdle(MapCameraPosition, byUserGesture:)`. As of M4.2 `byUserGesture`
    is `true` for **any** user pan/zoom/rotate gesture — however small — and
    `false` for programmatic camera moves. No distance/zoom threshold.
  - `MapMode` — `cruising` / `destinationPreview` / `navigating`. All three have
    realised camera framing. `MapViewModel.startNavigation()` (M4.3) drives the
    app into `.navigating` from the route preview; guidance beyond the maneuver
    card + dynamic zoom (off-route detection, rerouting, voice) is out of scope
    for M4.3.
  - `MapViewModel` — holds `any MapProvider` + `mode` + retained `camera` +
    `destination` + `route` + **`followsVehicle`** (M4.2) +
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
  - `ContentView` — the composition point: owns `MapViewModel`,
    `PlaceSearchViewModel`, `DestinationStore`, `RouteViewModel` (M3) and
    `NavigationViewModel` (M4.3); wires
    `searchVM.onDestinationChosen → destinationStore.select`,
    `destinationStore.destination → mapVM.setDestination` + `routeVM.requestRoute`
    (+ `navVM.stop()`), `routeVM.state (.loaded) → mapVM.setRoute`, the vehicle
    coordinate → `searchVM.origin` / routing origin / `navVM.update(with:)` →
    `mapVM.setNavigationProgress`, and the Start Navigation tap →
    `mapVM.startNavigation()` + `navVM.start(...)`. While navigating it swaps the
    search + route-status overlay for the maneuver card. The components don't
    know each other.
- **[Implemented]** Routing (M3 — see §5 item 26) + turn-by-turn (M4.3 — item 29):
  - `Route` — SDK-neutral: `polyline: [MapCoordinate]`, `distanceMeters`,
    `duration: Duration`, and **`steps: [RouteStep]`** (M4.3; `[]` for a route
    computed without step data). The drawn overview polyline is unchanged.
  - `RouteStep` (M4.3) — SDK-neutral maneuver: `ManeuverType` (turn/uturn/ramp/
    fork/roundabout/merge/straight/depart/arrive/nameChange/unknown, each with a
    `phrase`, an SF Symbol, and `warrantsCloserView`), `instruction`,
    `roadName?`, `maneuverPoint`, `polyline`, `distanceMeters`.
  - `RouteService` — provider-neutral `@MainActor` protocol:
    `route(from origin: MapCoordinate, to destination: MapCoordinate) async throws
    -> Route`; `RouteError` (`noRoute` / `unavailable`). **Separate from
    `MapProvider` and `PlaceSearchService`.**
  - `GoogleRouteService` — the Google **Routes API** (`POST
    routes.googleapis.com/directions/v2:computeRoutes`, `TRAFFIC_UNAWARE` DRIVE,
    encoded-polyline). **Imports Foundation only — no GMS types**; `URLSession`
    injected for tests; reuses `GoogleMapsConfiguration.apiKey` (`nonisolated`).
    Missing key / transport error / non-2xx (403 = API not enabled) → `.unavailable`;
    empty or degenerate route → `.noRoute`. **M4.3:** the field mask now also
    asks for `routes.legs.steps.{navigationInstruction,polyline,startLocation,
    endLocation,distanceMeters}`; private `Decodable` DTOs and the Google
    `Maneuver` → `ManeuverType` mapping + the "onto/on/toward" road-name
    heuristic all stay inside this file. Step fields bill at the Routes
    **Advanced** SKU (still free-tier for one user, once per trip — see §5/§9).
  - `GooglePolyline.decode(_:)` — pure encoded-polyline decoder.
  - `RouteGeometry` (M4.3) — pure geodesic helpers: haversine `distance`,
    polyline `length`, and `project(_:onto:)` (closest point on a polyline +
    distance-from-input + distance-along, via a local equirectangular frame).
  - `NavigationProgress` / `NavigationProgressCalculator` (M4.3) — the pure
    progress engine. Progress is one scalar `traveledMeters` along the
    concatenated step geometry; `stepIndex` is the upcoming maneuver,
    `distanceToManeuverMeters` / `distanceRemainingMeters` derived. `next(...)`
    only moves forward, advances the displayed maneuver by **at most one per
    fix** (`oneManeuverCap`), and **ignores a fix more than ~80 m off every
    step** so noise can't skip turns. No off-route detection / rerouting.
  - `NavigationViewModel` (M4.3) — `@MainActor`, mirrors the M3 `RouteViewModel`
    pattern (SDK-free, no `LocationStore`). `start(route:from:)` / `stop()` /
    `update(with:)`; `state` = `inactive` / `navigating(NavigationProgress)` /
    `arrived`; builds the `ManeuverCard` (icon + primary text + road + distance,
    or the arrival card).
  - `RouteViewModel` — SDK-free, holds no `LocationStore`: `requestRoute(to:from:)`
    takes the chosen `Destination?` + the latest origin (passed in by the
    composing view), exposes `state` (`idle` / `loading` / `loaded(Route)` /
    `noCurrentLocation` / `failed(RouteError)`), cancels any in-flight request.
    **No automatic rerouting** — a new request only happens on a destination
    change or an explicit Retry.
  - `MapViewModel.setRoute(_ route: Route?)` — sets `content.polylines` to one
    `MapPolyline(id: "route", …)` (or `[]`). **Never touches the camera** outside
    `.destinationPreview`. `setDestination(_:)` also clears the previous route +
    nav progress.
  - `RouteStatusView` — a small transient `.regularMaterial` pill under the
    search card: spinner + "Finding route…", "Waiting for GPS…", or "Route
    unavailable" + Retry. Nothing while idle or loaded. Hidden entirely once
    navigating.
  - `ManeuverCardView` / `ManeuverCard` / `NavigationDistance` (M4.3) — the
    top-of-map CarPlay-style card (large maneuver arrow, big distance, instruction
    + road, an "End" button) and its presentational model + distance formatter
    ("Now" / "220 m" / "1.4 km"). `StartNavigationButton` — the capsule action
    shown over the route preview. Both presentational; `ContentView` owns their
    visibility.
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
  **M4.2:** `applyCamera` handles `.navigation` (`viewingAngle` = pitch, bottom
  `mapView.padding` = viewport-height × `focusBelowCentre`); `.follow` / `.fit`
  reset the padding. `idleAt` reports `byUserGesture` from
  `UserGestureLatch` — a pure `nonisolated struct` (unit-tested, no GMS) that
  `willMove(byGesture:)` latches on for any user gesture and `idleAt` consumes.
  The latch is deliberate: a programmatic follow animation can fire *between* a
  gesture starting and the camera settling, reporting `byGesture: false`; that
  must not erase that the user is interacting. **No distance or zoom threshold** —
  any real pan/zoom/rotate, however small, drops follow; a purely programmatic
  move never sets the latch, so there is no feedback loop.
  **M4.3:** no `GoogleMapProvider` change — the dynamic navigation zoom rides in
  on `MapCameraState.zoom` inside the existing `.navigation` plan, which the
  camera-move path already applies.
- **[Implemented]** `GoogleMapsConfiguration` — reads `GoogleMapsAPIKey` from the
  bundle (build-injected, see §9), exposes it as `apiKey`, and calls
  `GMSServices.provideAPIKey`; returns `false` and does nothing if unset. No key
  in source. `GooglePlacesConfiguration.bootstrap()` reuses the same `apiKey` for
  `GMSPlacesClient.provideAPIKey`. Both are called from `DashApp.init()`.
- **[Implemented]** `ContentView` currently renders a full-screen `DashMapView`
  with the `MapSearchView` + `RouteStatusView` overlay (temporary shell — this is
  **not** the dashboard layout).
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
- **[Verified · automated]** `RouteTests` (M3 + M4.3): `Route` equality + metric
  retention; `GooglePolyline.decode` against Google's reference string, empty,
  and truncated input; `GoogleRouteService.makeRequest` (POST, endpoint, key +
  field-mask headers **incl. the M4.3 step fields**, DRIVE body with the right
  lat/lngs) and `parseRoute` from canned JSON (success, empty `routes`,
  degenerate 1-point polyline, malformed JSON) + duration parsing; **M4.3**:
  `parseRoute` builds `RouteStep`s from `legs[].steps[]` (maneuver / geometry /
  road name / point), a legs-less response still parses to a step-less `Route`,
  the Google `Maneuver` → `ManeuverType` table, and the "onto/on/toward"
  road-name heuristic; `GoogleRouteService` end-to-end with a **mocked
  `URLSession`** (200 → route, 403 → `.unavailable`, transport throw →
  `.unavailable`, no key → `.unavailable` with no network call); `RouteViewModel`
  (loads via a stub service, `noCurrentLocation` when origin is nil and no
  service call, `.failed` on `RouteError`, unexpected error normalised, clear →
  idle, new request cancels the in-flight one); `MapViewModel.setRoute` (one
  keyed polyline, `nil` clears, a new destination clears the old route; **in
  `.destinationPreview` the loaded route re-fits the `.fit` camera to
  vehicle + destination + route, clearing it re-fits back, a later fix does not
  move it; in `.cruising` the camera is never touched**). **The live Routes API
  is not called** — canned data / a mock transport stand in.
- **[Verified · automated]** `NavigationTests` (M4.3): `RouteGeometry` (haversine,
  polyline length, point→polyline projection incl. end-clamping);
  `NavigationProgressCalculator` — initial maneuver + distance, distance-to-
  maneuver shrinks along a step, passing a maneuver advances by one, **a single
  on-route fix two maneuvers ahead advances only one**, **a fix ~2 km off-route
  is ignored and progress is unchanged**, progress is monotonic, walking the whole
  route flips `isArrived`, a step-less route is benign; `NavigationViewModel` —
  starts inactive, `start` needs a route + an origin, updates advance the card,
  arrival shows the arrival card, `stop` resets; `ManeuverCard` / `NavigationDistance`
  formatting + `ManeuverType` phrase/symbol/`warrantsCloserView`; `MapViewModel`
  navigation camera — `startNavigation()` is gated on route + fix + preview mode,
  the plan tilts + sits the vehicle below centre, **no progress → base zoom**,
  **nearing a significant turn zooms in and eases back to base after**, a
  non-significant maneuver never zooms, the zoom is quantised to a handful of
  0.5-steps, **follow-off freezes the camera against progress updates**, recenter
  restores navigation follow, leaving navigation clears the progress + zoom.
  **No SDK, no live Routes API.**
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
  unit tests. Working tree (not committed).

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

### Automated test totals (all passing, 2026-09-02)

| Suite | Tests | Runner |
|---|---:|---|
| `DashSharedTests` | 8 | `swift test` |
| `DashRelayTests` | 32 | `xcodebuild ... -scheme DashRelay` (iOS Simulator) |
| `DashTests` | 202 (per the Xcode test plan; incl. 1 no-op scaffold; +29 M3, +12 M4.1, +20 M4.2, +37 M4.3) | `xcodebuild ... -scheme Dash` (iOS Simulator) |

Last full run (`xcodebuild test -scheme Dash -only-testing:DashTests`, iPad
simulator, 2026-09-02, with M4.3 in the working tree): all pass (**TEST
SUCCEEDED**, 202 / 202, 0 failures), build clean (app + device) with no warnings.

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
(M3 + M4.3 step/maneuver parsing) + `GoogleRouteServiceTests` + `RouteViewModelTests`
+ `MapViewModelRouteTests` in `RouteTests.swift`; `VehicleIndicatorTests` +
`GoogleMapVehicleStyleTests` (M4.1) in `VehicleIndicatorTests.swift`;
`CruisingFollowTests` + `PreviewUnchangedTests` + `NavigatingCameraTests` +
`UserGestureLatchTests` (20 total, M4.2) in `CameraFollowTests.swift`;
`RouteGeometryTests` + `NavigationProgressTests` + `NavigationViewModelTests` +
`ManeuverCardModelTests` + `NavigationCameraTests` (M4.3) in `NavigationTests.swift`.
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

11. **`ContentView` temporarily shows the full-screen map** so the Google Maps
    integration could be exercised end to end. This is a throwaway shell, not the
    dashboard layout.

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
      `ConnectedControlView` is overlaid on `ContentView` by `RootView` (the
      composition point — `ContentView`/map are untouched). It offers
      **Disconnect** (keeps pairing) and **Forget `<name>`** via a confirmation
      dialog. Extends §5 decision 17 (both connection views presentational; the
      container wires them) to the connected state.
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
      `viewingAngle` = pitch and bottom `mapView.padding` = viewport-height ×
      `focusBelowCentre` so the vehicle sits below centre with more road ahead;
      `state.headingDegrees` becomes the camera bearing. `.follow` / `.fit` reset
      the padding. Constants live on `MapViewModel`
      (`navigationPitchDegrees = 55`, `navigationFocusBelowCentre = 0.28`).
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
      zoom). Working tree — not committed.

---

## 6. Current limitations / known issues

- **No dashboard UI.** Behind the connection gate, `ContentView` is a bare
  full-screen map. There is no tile layout, no theming, no "GPS signal lost"
  banner surfaced to the user (the `LocationStore.signal` state exists but
  nothing displays it).
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
- **`ConnectedControlView` overlays the placeholder `ContentView`.** It is
  attached in `RootView`, not in `ContentView`/the map, so it moves cleanly when
  `Home/DashboardView` replaces the shell — but until then it floats over a
  full-screen map with no designed placement.
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
- **M4.3: off-route / wrong-turn handling is out of scope.** Progress worked on
  the verification drive, but there is no off-route detection or rerouting — if
  the driver misses a turn the card stays on the stale maneuver until they rejoin
  the route. A route that doubles back close to the vehicle can also mis-snap.
  The ~80 m off-route-ignore threshold only stops a noisy fix from *skipping*
  maneuvers; it does not detect being genuinely off-route. (M4.4+.)
- **M4.3: `NavigationViewModel` does not observe `LocationStore` itself.**
  `ContentView` pumps each fix into `navVM.update(with:)` and relays
  `progress` to `MapViewModel` — consistent with `RouteViewModel`, but it means
  the nav progress only advances while `ContentView` is on screen (fine today —
  it is the only screen).
- **M4.3: road names are parsed from instruction text.** The Routes API gives no
  dedicated street field per step, so `roadName` comes from an "onto/on/toward"
  heuristic on the instruction string. It handles the common phrasings; unusual
  instructions fall back to showing the full instruction with no separate road
  line.
- **M4.3: the maneuver arrow set is approximate.** `ManeuverType.symbolName`
  maps to SF Symbols; a few (sharp turns, forks, ramps) reuse near-neighbours
  rather than exact glyphs.
- **M4.3: no ETA / distance-remaining shown.** `NavigationProgress` carries
  `distanceRemainingMeters` and `Route.duration`, but the card only shows the
  next maneuver — an ETA / trip panel is a later task.
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
- **[Planned]** `Home/DashboardView` — the CarPlay-style tile layout that
  assembles map + music + speedometer (the single layout owner); replaces the
  `RootView → ContentView` full-screen-map shell.
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
  dynamic navigation zoom. Physically verified on the iPad (§3, §10). Working tree
  — not committed.
- **[Planned]** Map layer depth, remaining (the rest of **M4**): off-route
  detection + rerouting, alternative routes, an ETA / trip panel, voice guidance,
  lane guidance. Also: turning a map POI tap (`MapEvent.tappedPOI`) into a
  destination; an Apple `MKDirections` `RouteService`.
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
4. **`DashboardView` skeleton** — placeholder tiles to validate the CarPlay-style
   layout; move the map into a tile (retire the `RootView → ContentView` shell).
5. **Speedometer + trip computer** — derived from `LocationStore` (smoothing,
   km/h, `TripStats`).
6. **Music** — MusicKit catalog search + custom player.
7. **`AppleMapProvider` + Settings toggle** — second provider, persisted choice.

Map-feature sub-track (independent of the above ordering; **M1 + M2 + M3 + M4.1 +
M4.2 committed; M4.3 in the working tree**):
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
- **M4.3 [done, device-verified, unit-tested (+37); not committed]** —
  `Route.steps` / `RouteStep`, `GoogleRouteService` step + maneuver mapping, the
  pure `RouteGeometry` / `NavigationProgressCalculator` engine,
  `NavigationViewModel`, the `ManeuverCardView` + `StartNavigationButton`,
  `MapViewModel.startNavigation()` and the quantised dynamic navigation zoom.
  §5 item 29. **Guidance display + camera only** — no off-route detection /
  rerouting / alternatives / voice / lane guidance / dashboard.
- **M4.4+** — off-route detection + rerouting, alternative routes, an ETA / trip
  panel; then heading smoothing, voice guidance, and the POI-tap → destination
  path.
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

### Google Cloud — required for M3 routing + M4.3 turn-by-turn  ✅ confirmed working

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

### Google Maps cost discipline (spec §5)

- Maps SDK map view: free/unlimited.
- Places **Autocomplete**: free ≤ 10k requests/month; a `GMSAutocompleteSessionToken`
  groups a keystroke run + the details fetch into one cheaper billing session
  (the Google impl already does this). Comfortably free at single-user volume.
- Places **Details (New)**: billed per field group; one call per chosen
  destination — negligible at this volume.
- **Routes API "Compute Routes"** (M3 + M4.3): billed **per request**.
  `RouteViewModel` fires exactly one request per destination selection / Retry —
  no timer, no re-request on a new fix; `startNavigation()` reuses the already-
  loaded route. `TRAFFIC_UNAWARE` keeps traffic pricing off; the M4.3 field mask
  adds `routes.legs.steps.*` (→ "Advanced" SKU). ~60–90 trips/month is within the
  monthly free allowance. Re-routing (a timer / off-route re-request) is
  explicitly M4.4+, not M4.3.

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
| *(working tree, uncommitted)* | **Map "M4.3": start navigation & maneuver guidance** (guidance display + camera only — **no** off-route detection, rerouting, alternative routes, traffic switching, voice, lane guidance, ETA, or dashboard work). `Route` gained **`steps: [RouteStep]`** (SDK-neutral `ManeuverType` + instruction + road name + point + step polyline + distance; defaults `[]`). `GoogleRouteService`: field mask adds `routes.legs.steps.*`, private DTOs + the Google `Maneuver` → `ManeuverType` table + an "onto/on/toward" road-name heuristic all stay in-file (step fields = Routes **Advanced** SKU, still free-tier once-per-trip). New pure engine in `Routing/`: **`RouteGeometry`** (haversine / polyline length / point→polyline projection) and **`NavigationProgressCalculator`** — progress is one monotone `traveledMeters` scalar; a fix advances the displayed maneuver **by ≤ 1** and a fix > ~80 m off every step is ignored, so noise never skips a turn. **`NavigationViewModel`** (`@MainActor`, mirrors `RouteViewModel`; `inactive` / `navigating(NavigationProgress)` / `arrived`) builds a **`ManeuverCard`**. **`ManeuverCardView`** (top-of-map, CarPlay-style: arrow + big distance + instruction/road + End) and **`StartNavigationButton`** are presentational; `ContentView` swaps the search + route-status overlay for the card while navigating and wires the fix pump → `navVM.update` → `mapVM.setNavigationProgress`. **`MapViewModel.startNavigation()`** (gated on route + a fix + preview mode) enters `.navigating`; the follow camera keeps M4.2's tilt/below-centre framing and overrides the zoom via pure **`navigationZoom(...)`** — base until ~350 m from a `warrantsCloserView` maneuver, ramping to `+1.5` by ~40 m, **quantised to 0.5 steps**, easing back after; follow-off freezes it; recenter restores nav follow. **No `GoogleMapProvider` change.** Tests: new **`NavigationTests` (+~33)** + `RouteTests` (+4). Build clean (app + device), no warnings; full `DashTests` green (202 / 202). **Physically verified on the iPad** — Start Navigation, maneuver card + live updates, route progress, navigation follow / recenter, dynamic maneuver zoom all work. §5 item 29. |
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
  Google step/maneuver parsing (canned JSON). Not committed. Off-route detection
  / rerouting / voice remain out of scope (M4.4+).
