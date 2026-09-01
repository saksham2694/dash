# PROJECT_STATUS.md

Living status document for **Dash**. It describes the repository as it actually
stands so a future developer (or a fresh Claude Code session) can get oriented
without conversation history.

- **Last updated:** 2026-09-02
- **Branch:** `main`
- **Latest commit:** `973ffc9 feat(map): add destination search` — the Map **M1**
  (rendering-boundary widening) and **M2** (destination search) work is committed
  here, along with the search-result-row contrast fix below.
- **Everything through M2 is committed.** The connection/pairing/relay-status work
  (previously "working tree" in this doc) landed in `9a02364` / `ec4d4a9` /
  `c3a3a18`; the Map M1 + M2 work landed in `973ffc9`. See §10 for the mapping.
- **Most recent follow-up (in `973ffc9`):** on-device testing of M2 autocomplete
  showed the suggestion-row **secondary line and trailing distance were invisible**
  — `.foregroundStyle(.secondary)` / `.tertiary` are translucent and wash out
  against `MapSearchView`'s `.regularMaterial` card over the bright map. Both
  changed to an explicit opaque `Color(uiColor: .systemGray)` in `MapSearchView`
  (styling only — no layout, data, or SDK change). Google autocomplete and
  `GooglePlaceSearchService`'s field mapping were confirmed correct on device via
  temporary logging (since removed).
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
    │       ├── MapCameraState.swift            # camera value type + following(_:); MapCameraPlan (.follow / .fit)
    │       ├── MapContent.swift                # the render state: camera plan, vehicle, polylines, markers
    │       ├── MapOverlay.swift                # MapPolyline + MapMarker (identified, diffable overlay descriptors)
    │       ├── MapEvent.swift                  # taps (map / POI / marker) + camera-idle; MapPOI, MapCameraPosition
    │       ├── MapMode.swift                   # cruising / destinationPreview / navigating (only cruising is realised)
    │       ├── MapViewModel.swift              # holds provider + mode + destination; derives MapContent; setDestination(_:); routes MapEvent
    │       ├── DashMapView.swift               # neutral SwiftUI component
    │       ├── GoogleMapProvider.swift         # ONLY Map file importing GoogleMaps; wraps GMSMapView, diffs overlays, bridges the delegate
    │       └── Search/                         # M2 — destination search (all SDK-neutral except GooglePlaceSearchService.swift)
    │           ├── Destination.swift           # Destination + PlaceSuggestion value types
    │           ├── PlaceSearchService.swift    # provider-neutral protocol (suggestions / details) + PlaceSearchError
    │           ├── GooglePlaceSearchService.swift  # ONLY Map file importing GooglePlaces; autocomplete + place details (New), session token
    │           ├── DestinationStore.swift      # @MainActor ObservableObject — the chosen Destination? (source of truth)
    │           ├── PlaceSearchViewModel.swift  # SDK-free: debounce, suggestions, resolve-to-Destination via onDestinationChosen
    │           └── MapSearchView.swift         # custom search field + suggestions list + selected-destination chip (presentational)
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
- **The map is isolated behind `MapProvider`; search is isolated behind
  `PlaceSearchService`.** `import GoogleMaps` appears in exactly two files
  (`GoogleMapProvider.swift`, `GoogleMapsConfiguration.swift`); `import GooglePlaces`
  in exactly two (`GooglePlaceSearchService.swift`, `GooglePlacesConfiguration.swift`).
  Every other Map / Search file is SDK-free. `MapProvider` is **rendering only**
  (a `MapContent` value in, a `MapEvent` closure back) — it has no search /
  routing / place methods. Place search / autocomplete / details live on the
  **separate `PlaceSearchService` protocol** (M2), so a MapKit provider can back
  it with `MKLocalSearch` without touching the renderer. The chosen destination
  is SDK-neutral (`Destination`) and held in its own `DestinationStore`.
- **The map receives state as input, emits events as output.** `MapViewModel`
  holds no `LocationStore` reference, no networking, no GPS. It converts a
  `LocationPacket` into a follow `MapCameraState` (pure `following(_:)`), assembles
  the full `MapContent` (camera plan + vehicle + overlays) for the active
  `MapMode`, and routes `MapEvent`s back. Overlay lists and the non-`cruising`
  modes are modelled but not yet populated (no routes/search exist).
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
  - `MapCameraState` — unchanged value type (lat/lon/`headingDegrees?`/zoom +
    `.default` + `following(_:)`), now also `center`. `MapCameraPlan` — `.follow(MapCameraState)`
    or `.fit(MapCoordinateBounds, padding:)` (the fit case is unused until routing).
  - `MapContent` — the full render state: `camera: MapCameraPlan`, `vehicle: MapCoordinate`,
    `polylines: [MapPolyline]`, `markers: [MapMarker]`. `Equatable` for provider-side diffing.
  - `MapOverlay` — `MapPolyline` (`id` + `coordinates`) and `MapMarker`
    (`id` + `coordinate` + `title?`), both `Identifiable`.
  - `MapEvent` — `.tappedMap` / `.tappedPOI(MapPOI)` / `.tappedMarker(id:)` /
    `.cameraIdle(MapCameraPosition, byUserGesture:)`.
  - `MapMode` — `cruising` / `destinationPreview` / `navigating`. As of M2
    `destinationPreview` is realised (a chosen destination); `navigating` still
    falls back to follow.
  - `MapViewModel` — holds `any MapProvider` + `mode` + the retained follow
    `camera` + the current `destination`; `update(with:)` re-centres and rebuilds
    `content` (but leaves the camera alone while previewing); `setMode(_:)`;
    **`setDestination(_:)`** (M2 — drops/removes the pin, frames vehicle +
    destination, toggles `.destinationPreview` ⟷ `.cruising`); `handle(_ event:)`
    (still a documented no-op seam).
  - `DashMapView` — neutral component; feeds `location` in via `.onChange` /
    `.onAppear`, forwards `MapEvent`s to `viewModel.handle`.
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
    `PlaceSearchViewModel`, `DestinationStore`; wires
    `searchVM.onDestinationChosen → destinationStore.select`,
    `destinationStore.destination → mapVM.setDestination`, and the vehicle
    coordinate → `searchVM.origin`. The three components don't know each other.
- **[Implemented]** `GoogleMapProvider` — the live Google Maps view, and the only
  Map file importing `GoogleMaps`. Wraps `GMSMapView` in a private
  `UIViewRepresentable`; the `Coordinator` owns the vehicle `GMSMarker` plus
  keyed dictionaries of route `GMSPolyline`s / destination `GMSMarker`s and
  **diffs each `MapContent`** against the last render (camera / vehicle /
  polylines / markers applied only on change); it is the `GMSMapViewDelegate` and
  translates tap + `idleAt` callbacks (with a `willMove(byGesture:)` flag) into
  `MapEvent`s. `isMyLocationEnabled = false` (position comes from the relay, not
  the iPad's own CoreLocation). Existing behaviour preserved: vehicle marker,
  follow camera, `.follow` animation on update. Overlay rendering paths exist but
  receive no data yet.
- **[Implemented]** `GoogleMapsConfiguration` — reads `GoogleMapsAPIKey` from the
  bundle (build-injected, see §9), exposes it as `apiKey`, and calls
  `GMSServices.provideAPIKey`; returns `false` and does nothing if unset. No key
  in source. `GooglePlacesConfiguration.bootstrap()` reuses the same `apiKey` for
  `GMSPlacesClient.provideAPIKey`. Both are called from `DashApp.init()`.
- **[Implemented]** `ContentView` currently renders a full-screen `DashMapView`
  with the `MapSearchView` overlay (temporary shell — this is **not** the
  dashboard layout).
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
- **[Verified · automated]** `MapContentTests` (16): `MapCoordinateBounds`
  — empty → `nil`, single coordinate → degenerate box, spans min/max lat & lon,
  centre is the midpoint; `MapViewModel` — starts `.cruising` with no overlays and
  `.follow(.default)`, a fix moves vehicle + follow camera together, `nil` fix is
  a no-op, zoom persists across fixes, `setMode` fallback; **M2**: `setDestination`
  drops a pin + enters `.destinationPreview`, the preview camera `.fit`s vehicle +
  destination, a later fix moves the vehicle but not the camera, clearing removes
  the pin and resumes `.follow`, a nameless destination → titleless marker.
- **[Verified · automated]** `PlaceSearchTests` (11): `DestinationStore`
  select/clear; `PlaceSearchViewModel` (stub service) — a sub-minimum query
  doesn't hit the service, a valid query publishes suggestions, `origin` is
  forwarded for biasing, a service failure clears results + shows an error, the
  debounced path runs, clearing the query wipes results, `choose` resolves →
  `onDestinationChosen` + field reset, a failed resolve shows an error + hands
  out nothing, `reset` clears. **Google's SDK is not exercised** — a stub stands in.
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
| `DashTests` | 104 (per the Xcode test plan; incl. 1 no-op scaffold) | `xcodebuild ... -scheme Dash` (iOS Simulator) |

Last full run (`xcodebuild test -scheme Dash -only-testing:DashTests`, iPad
simulator, 2026-09-02): all pass, build clean with no warnings.

`DashSharedTests` breakdown: `LocationPacketTests` (4), `RelayAdvertisementTests` (4).
`DashRelayTests` breakdown: `LocationTrackerTests` (7), `LocationBroadcasterTests`
(7), `RelayIdentityTests` (4), `RelaySessionControllerTests` (8),
`RelayStatusViewTests` (6).
`DashTests` (connection/pairing-relevant): `ConnectionCoordinatorTests` (22),
`ConnectionSetupViewTests` (8), `ConnectedControlViewTests` (2),
`KnownDeviceStoreTests` (7), `LocationReceiverTests` (7).
`DashTests` (map): `MapCameraStateTests` (4) + `MapViewModelTests` (3) in
`MapCameraStateTests.swift`; `MapCoordinateBoundsTests` (4) +
`MapViewModelContentTests` (12) in `MapContentTests.swift`;
`DestinationStoreTests` (2) + `PlaceSearchViewModelTests` (9) in
`PlaceSearchTests.swift`.
(Map / search have no SDK-level tests — `GoogleMapProvider` / `GMSMapView` /
`GooglePlaceSearchService` / `GMSPlacesClient` stay device-validated.)

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
- **Partly-exercised map plumbing.** As of M2 `MapContent.markers`, the `.fit`
  camera plan, and `MapMode.destinationPreview` are driven by a chosen
  destination. Still inert until later milestones: `MapContent.polylines` and
  `.navigating` (routing / nav), and every `MapEvent` case —
  `MapViewModel.handle(_:)` is still a no-op, so a POI tap on the map does **not**
  yet become a destination (only the search field does).
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
  `.markers` / `.fit` / `.destinationPreview` are now driven by M2; `.polylines`
  and `MapEvent` consumption still await routing / navigation.
- **[Implemented]** Destination search (§5 item 25): `PlaceSearchService` +
  `GooglePlaceSearchService` (Places SDK), `PlaceSearchViewModel`,
  `DestinationStore`, `MapSearchView`, `MapViewModel.setDestination(_:)`.
  "Places API (New)" is enabled and autocomplete is device-verified (§3);
  Place Details resolve + pin + preview camera are still device-unverified (§6).
- **[Planned]** Map layer depth, remaining: **`RoutingService`** (route once per
  trip — Routes API), a **separate protocol** from `MapProvider` and
  `PlaceSearchService`, Google impl then Apple impl. Then a provider-neutral
  guidance engine driven by `LocationStore` + the cached route. Also: turning a
  map POI tap (`MapEvent.tappedPOI`) into a destination. (See the map-roadmap
  investigation; not started.)
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

Map-feature sub-track (independent of the above ordering; **M1 + M2 done**):
- **M1 [done]** — widen the rendering boundary for overlays / events / modes
  (§5 item 24).
- **M2 [done]** — `PlaceSearchService` + Google impl, `PlaceSearchViewModel` /
  `DestinationStore`, custom `MapSearchView`, destination pin + preview camera
  (§5 item 25). "Places API (New)" is enabled; autocomplete + the suggestion list
  are device-verified. Still to check on device: choosing a suggestion (Place
  Details resolve), the pin, and the preview camera (§6).
- **M3** — `RoutingService` (Routes API, once per trip) + route polyline on the
  map via the M1 overlay channel; reuse the M2 destination.
- **M4** — provider-neutral guidance engine (maneuver card, off-route detection,
  navigation camera) driven by `LocationStore` + the cached route.
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
   (Routing later will additionally need the **Routes API** enabled — not yet done.)

If Places access were ever revoked, autocomplete / details requests return an
error and `PlaceSearchViewModel` shows its generic "Couldn't search" text.

### Google Maps cost discipline (spec §5)

- Maps SDK map view: free/unlimited.
- Places **Autocomplete**: free ≤ 10k requests/month; a `GMSAutocompleteSessionToken`
  groups a keystroke run + the details fetch into one cheaper billing session
  (the Google impl already does this). Comfortably free at single-user volume.
- Places **Details (New)**: billed per field group; one call per chosen
  destination — negligible at this volume.
- Directions/Routes (later): billed **per request** — call once per trip, never
  on a timer; track against the cached route locally.

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
