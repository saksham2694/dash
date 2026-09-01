# PROJECT_STATUS.md

Living status document for **Dash**. It describes the repository as it actually
stands so a future developer (or a fresh Claude Code session) can get oriented
without conversation history.

- **Last updated:** 2026-09-01
- **Branch:** `main`
- **Latest commit:** `9ccf6e0 feat(connection): add setup screen`
- **Working tree (not yet committed as of this update):** the **first DashRelay
  connection/status UI** (`RelayStatusScreen` / `RelayStatusView` — §3 "DashRelay",
  §5 item 18).
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
│   │   ├── LocationPacket.swift     # Codable wire model: latitude, longitude, speed, heading, timestamp
│   │   └── LocationWireFormat.swift # bonjourServiceType "_dashrelay._tcp", ISO-8601 JSON coder, \n framing
│   └── Tests/DashSharedTests/
│       └── LocationPacketTests.swift
└── Dash/
    ├── Dash.xcodeproj               # one project, 6 targets: Dash, DashTests, DashUITests,
    │                                #   DashRelay, DashRelayTests, DashRelayUITests
    ├── Config/
    │   ├── GoogleMapsService.xcconfig          # git-ignored, holds the real API key
    │   └── GoogleMapsService.xcconfig.template # committed template
    ├── Dash/                        # iPad app target
    │   ├── DashApp.swift            # @main; owns LocationStore + ConnectionCoordinator + KnownDeviceStore; bootstraps Google Maps
    │   ├── RootView.swift           # connection gate: ContentView when isConnected, else ConnectionSetupView
    │   ├── ContentView.swift        # full-screen DashMapView (the "dashboard" behind the gate for now — placeholder shell)
    │   ├── Info.plist               # NSBonjourServices, GoogleMapsAPIKey = $(GOOGLE_MAPS_API_KEY)
    │   ├── Configuration/
    │   │   └── GoogleMapsConfiguration.swift   # reads key from Info.plist, calls GMSServices.provideAPIKey
    │   ├── Core/
    │   │   ├── LocationReceiver.swift          # NWBrowser + NWConnection, reconnect loop; Status now carries connectedServiceName
    │   │   ├── LocationReceiving.swift         # protocol seam over LocationReceiver (DI for ConnectionCoordinator tests)
    │   │   ├── PacketLineBuffer.swift          # reassembles \n-delimited JSON → [LocationPacket]
    │   │   ├── LocationStore.swift             # single source of truth for location DATA + watchdog (no longer owns the transport)
    │   │   ├── ConnectionState.swift           # enum: disconnected / discovering / connecting / connected
    │   │   ├── ConnectionCoordinator.swift     # session layer: owns the transport, maps phase→ConnectionState, feeds LocationStore
    │   │   └── KnownDeviceStore.swift          # pairing / known-device persistence (KnownRelay); separate from connection
    │   ├── Features/Connection/
    │   │   └── ConnectionSetupView.swift       # the not-connected / setup screen (presentational; own feature folder)
    │   └── Features/Map/
    │       ├── MapProvider.swift               # protocol boundary + MapProviderID enum
    │       ├── MapCameraState.swift            # SDK-neutral camera value type + following(_:)
    │       ├── MapViewModel.swift              # holds active provider + camera; transforms packets
    │       ├── DashMapView.swift               # neutral SwiftUI component
    │       └── GoogleMapProvider.swift         # ONLY file importing GoogleMaps; wraps GMSMapView
    │   # (spec-planned but NOT present: Models/, Features/Music, Features/Speedometer,
    │   #  Features/Settings, Home/DashboardView, Core/ThemeManager)
    ├── DashTests/                   # Swift Testing
    │   ├── LocationReceiverTests.swift
    │   ├── PacketLineBufferTests.swift
    │   ├── LocationStoreTests.swift
    │   ├── ConnectionCoordinatorTests.swift
    │   ├── ConnectionSetupViewTests.swift
    │   ├── KnownDeviceStoreTests.swift
    │   ├── MapCameraStateTests.swift
    │   └── DashTests.swift          # scaffold `example()` — no-op, still present
    ├── DashUITests/                 # Xcode scaffold only, no real tests
    └── DashRelay/                   # iPhone app target
        ├── DashRelayApp.swift       # @main; owns RelaySessionController (@StateObject), renders RelayStatusScreen, starts session in .task
        ├── Info.plist               # UIBackgroundModes:[location], NSLocalNetworkUsageDescription, NSBonjourServices
        ├── Features/Status/
        │   └── RelayStatusView.swift       # RelayStatusScreen (container) + RelayStatusView (presentational) + Display mapping
        ├── Services/
        │   ├── LocationTracker.swift       # wraps CLLocationManager; wantsTracking gate so auth callbacks can't revive GPS after stop()
        │   ├── LocationBroadcaster.swift   # NWListener advertised via Bonjour, \n-delimited JSON to N clients
        │   └── RelaySession.swift          # session layer: RelaySessionController (stopped/waiting/connected) + RelayTracking/RelayBroadcasting seams
        └── DashRelayTests/
            ├── LocationTrackerTests.swift
            ├── LocationBroadcasterTests.swift
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
RelaySessionController (stopped/waiting/         ConnectionCoordinator (disconnected/discovering/
  connected); start() → advertise + track,         connecting/connected); startSession()/disconnect()
  stop() → stop networking AND GPS                    │ owns the transport lifecycle
     │                                                ▼
CLLocationManager                                LocationReceiver (NWBrowser "_dashrelay._tcp"
  → LocationTracker.packet(from:)                  → NWConnection → receive loop)
  → onPacket (in didUpdateLocations)              → PacketLineBuffer.append(_:)  (split on \n, decode)
  → LocationBroadcaster.broadcast(_:)             → onPacket → ConnectionCoordinator
  → NWListener → all TCP clients ───JSON+\n──────▶ → LocationStore.ingest(_:)   ← SINGLE SOURCE OF TRUTH (location DATA)
                                                     ├─ @Published latestPacket / signal
                                                     └─ watchdog Task: no packet in staleInterval ⇒ signal = .stale
                                                            │
                                                  RootView: ContentView when
                                                  ConnectionCoordinator.isConnected, else ConnectionSetupView
                                                     → ContentView (observes LocationStore)
                                                     → DashMapView(viewModel:, location: latestPacket)
                                                     → MapViewModel.update(with:) → camera.following(packet)
                                                     → GoogleMapProvider → GMSMapView.animate(to:) + move marker
```

Connection state (`disconnected/discovering/connecting/connected`) lives **only**
in `ConnectionCoordinator`. `LocationStore` no longer tracks a link phase — it
owns location *data* and the data-freshness watchdog, which is a separate concern
(you can be `.connected` but `signal == .stale` if the relay is up but has no GPS
fix).

### Key architectural rules currently honoured

- **`LocationStore` is the only consumer of network data.** `LocationReceiver`
  pushes into it; features read from it. Nothing else opens a connection.
- **Wire types live in `DashShared`.** `LocationPacket` and `LocationWireFormat`
  (service type + JSON/date strategy + `\n` framing) are defined once. `DashRelay`
  and `Dash` both go through `LocationWireFormat`.
- **The map is isolated behind `MapProvider`.** `import GoogleMaps` appears in
  exactly two files: `GoogleMapProvider.swift` and `GoogleMapsConfiguration.swift`.
  `MapProvider` / `MapCameraState` / `MapViewModel` / `DashMapView` are SDK-free.
- **The map receives state as input.** `MapViewModel` holds no `LocationStore`
  reference, no networking, no GPS — it converts a `LocationPacket` into a
  `MapCameraState` via the pure `MapCameraState.following(_:)`.
- **Bonjour discovery, never a hardcoded IP** — on both sides.
- **Incidental disconnects are routine.** `LocationReceiver` re-browses and
  reconnects on a timer; `LocationStore`'s watchdog covers the UI gap. A
  **deliberate** disconnect is different — it stays disconnected (see below).
- **SwiftUI + MVVM**, `@MainActor` isolation, serial-queue-confined
  `@unchecked Sendable` classes for the Network-framework wrappers.

### Connection / session layer

A thin layer that sits **above** the networking and location layers — it does
not replace their responsibilities.

**Three separate concerns, three types:**

| Concern | Type | Owns |
|---|---|---|
| Current connection state + session lifecycle (iPad) | `ConnectionCoordinator` (`@MainActor ObservableObject`) | the `LocationReceiving` transport; `@Published connectionState` / `connectedDeviceName`; `startSession()` / `disconnect()` |
| Current session state (iPhone) | `RelaySessionController` (`@MainActor ObservableObject`) | `LocationTracker` + `LocationBroadcaster`; `@Published state` (`stopped`/`waiting`/`connected`) / `isTrackingLocation`; `start()` / `stop()` |
| Pairing / known devices (iPad) | `KnownDeviceStore` (`@MainActor ObservableObject`) | a persisted `[KnownRelay]` with `remember` / `forget` / `forgetAll` |

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
  see it. `ConnectionSetupView` is presentational — it takes a `ConnectionState`
  and action closures, so it holds no copy of the state.
- **DashRelay shows its session state.** `RelayStatusScreen` (the DashRelay root)
  reads `RelaySessionController` from the environment and hands `state` +
  action closures to the presentational `RelayStatusView`
  (`stopped` → Start, `waiting` → "Ready to Connect" + spinner, `connected` →
  Disconnect). Disconnect calls the existing `RelaySessionController.stop()`; the
  view contains no networking or GPS logic and keeps no copy of the state.
- **Pairing state is independent.** `KnownDeviceStore` and `ConnectionCoordinator`
  hold no reference to each other. `KnownRelay` is keyed by Bonjour service name
  (spec §4) and the store already supports multiple devices. The hook that links
  them later is `ConnectionCoordinator.connectedDeviceName`.

---

## 3. Implemented and verified functionality

### DashShared

- **[Implemented]** `LocationPacket` — `Codable, Equatable, Sendable`; fields
  `latitude`, `longitude`, `speed`, `heading` (`Double`), `timestamp` (`Date`).
  `speed`/`heading` keep `CLLocation`'s "negative = invalid" semantics.
- **[Implemented]** `LocationWireFormat` — shared `bonjourServiceType`
  (`"_dashrelay._tcp"`), `makeEncoder()`/`makeDecoder()` (ISO-8601 dates),
  `lineDelimiter` (`\n`), `encodeLine(_:)`.
- **[Verified · automated]** `LocationPacketTests` (4 tests): JSON round-trip,
  invalid-fix sentinels survive, decoding a fixed payload, exact key set.

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
  `_dashrelay._tcp` service; accepts multiple concurrent TCP clients; sends each
  packet as one `\n`-terminated JSON line; clean connect/disconnect handling; a
  main-actor `onStatusChange` hook (`isListening`, `clientCount`).
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
  the first DashRelay connection/status UI. `RelayStatusScreen` is the container
  that reads `RelaySessionController` (single source of truth) from the
  environment; `RelayStatusView` is presentational — it takes the `State` plus
  `onStart` / `onDisconnect` closures and holds no copy of the state. Screens:
  a **startup/waiting screen** when not connected (`stopped` → "Relay Stopped" +
  a **Start** button that calls `session.start()`; `waiting` → "Ready to Connect"
  + spinner + a note that a Dash iPad on the same Wi‑Fi should be opened, no
  button) and a **connected screen** (`connected` → "Connected" + a **Disconnect**
  button that calls the existing `RelaySessionController.stop()`, which returns
  the session to `.stopped`/waiting). The connected screen shows a **generic
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
- **[Verified · automated]** `LocationBroadcasterTests` (5): service type,
  single-`\n` framing, line decodes back, multi-line stream splits, lifecycle
  no-ops.
- **[Verified · automated]** `RelaySessionControllerTests` (8): `stopped→waiting`
  on `start()` (advertising + GPS begin), `waiting→connected` when a client
  attaches and back, `connected→stopped` on `stop()` (broadcaster + tracker
  stopped), **stopping the session stops tracking**, **a deliberate disconnect
  does not immediately reconnect** (trailing status ignored), resume after stop,
  fixes forwarded to the broadcaster.
- **[Verified · automated]** `RelayStatusViewTests` (5): the `Display` `State` →
  screen mapping — `stopped` offers *Start* with no activity indicator; `waiting`
  shows the activity indicator, offers no action ("Ready to Connect"); `connected`
  offers *Disconnect* with no activity indicator; every state has non-empty
  title/message/symbol; **Disconnect is offered only when connected**.
- **[Verified · simulator]** `RelayStatusView` rendered on the iPhone simulator in
  the `waiting` state (portrait and landscape): antenna symbol, "Ready to
  Connect", spinner, explanatory text, no button; content stays centred and
  width-capped. `stopped` / `connected` are covered by the unit tests, not this
  manual check.
- **[Implemented]** DashRelay app builds and launches; the root is now
  `RelayStatusScreen`.

### Dash (iPad)

- **[Implemented]** `LocationReceiver` — `NWBrowser` for `_dashrelay._tcp`,
  connects to the first discovered endpoint, receive loop feeding
  `PacketLineBuffer`; automatic re-browse/reconnect after a delay on any
  *incidental* drop/failure (suppressed after a deliberate `stop()`); `Status`
  phases `stopped / browsing / connecting / connected` plus
  `connectedServiceName` (the Bonjour name of the relay reached, for pairing)
  via a main-actor `onStatusChange`. Conforms to `LocationReceiving`.
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
- **[Implemented]** `ConnectionCoordinator` — the iPad session layer. Owns a
  `LocationReceiving`; `@Published connectionState` (`disconnected` /
  `discovering` / `connecting` / `connected`) and `connectedDeviceName`;
  `isConnected`; `startSession()` / `disconnect()`; feeds packets into
  `LocationStore`; a deliberate `disconnect()` stays disconnected and ignores
  trailing transport status. Pure `connectionState(for:)` phase mapping.
- **[Implemented]** `KnownDeviceStore` — `@MainActor ObservableObject` +
  `KnownDeviceStoring`; a `[KnownRelay]` (keyed by Bonjour service name)
  persisted as JSON in `UserDefaults`; `remember` / `forget` / `forgetAll` /
  `isKnown`; supports multiple devices. **This is storage only** — nothing
  decides *when* to remember a device yet.
- **[Implemented]** `RootView` — gates the UI: `ContentView` (dashboard) when
  `ConnectionCoordinator.isConnected`, otherwise `ConnectionSetupView`. Wires the
  setup screen's actions to `connection.disconnect()` / `connection.startSession()`.
- **[Implemented]** `ConnectionSetupView` (`Features/Connection/`) — the first
  connection/setup screen, shown whenever Dash is not connected. Presentational:
  takes a `ConnectionState` + `onDisconnect` / `onReconnect` closures (no state
  copy). Communicates *not connected*, whether it is *discovering / connecting*
  (spinner + status line), and that a **DashRelay iPhone on the same Wi‑Fi** is
  needed. Action shown *only when appropriate*: **Disconnect** while
  `discovering` / `connecting`; **Search for DashRelay** while `disconnected`
  (idle after a deliberate disconnect); nothing while `connected`. A nested
  `ConnectionSetupView.Display` value type does the pure state → display mapping.
  Layout is `GeometryReader` + `ScrollView` with a centred, width-capped
  (`maxWidth: 460`) content column — works in iPad portrait and landscape (and
  on iPhone). **No pairing controls.** Visuals are intentionally plain.
- **[Implemented]** `DashApp` owns `LocationStore`, `ConnectionCoordinator`, and
  `KnownDeviceStore` as `@StateObject`s, injects them as `environmentObject`s,
  calls `connection.startSession()` in `.task`, and
  `GoogleMapsConfiguration.bootstrap()` in `init()`.
- **[Implemented]** Map abstraction: `MapProvider` protocol (`id`,
  `makeMapView(camera:) -> AnyView`), `MapProviderID` enum
  (`googleMaps`, `appleMaps`), `MapCameraState` (lat/lon/`headingDegrees?`/zoom
  + `.default` + `following(_:)`), `MapViewModel` (holds `any MapProvider` +
  camera; `update(with:)`), `DashMapView` (neutral component; feeds `location`
  into the view model via `.onChange`/`.onAppear`).
- **[Implemented]** `GoogleMapProvider` — the live Google Maps view. Wraps
  `GMSMapView` in a private `UIViewRepresentable`; a `Coordinator` holds a
  `GMSMarker` for the vehicle position; `updateUIView` animates the camera and
  moves the marker; `isMyLocationEnabled = false` (position comes from the relay,
  not the iPad's own CoreLocation).
- **[Implemented]** `GoogleMapsConfiguration` — reads `GoogleMapsAPIKey` from the
  bundle (build-injected, see §9) and calls `GMSServices.provideAPIKey`; returns
  `false` and does nothing if unset. No key in source.
- **[Implemented]** `ContentView` currently renders a full-screen `DashMapView`
  (temporary shell — this is **not** the dashboard layout).
- **[Verified · automated]** `PacketLineBufferTests` (9): single line, two lines
  per chunk, line split across chunks, partial trailing line held, blank lines
  ignored, malformed line skipped, oversized line dropped then recovers, `reset()`,
  round-trip against `LocationWireFormat`.
- **[Verified · automated]** `LocationStoreTests` (10): initial state, ingest
  becomes source of truth, latest-wins, live within interval, goes stale, stale
  retains packet, recovers after stale, watchdog `Task` fires on its own,
  `connectionEnded()` returns to `.waiting` keeping the last packet,
  `connectionEnded()` stays `.waiting` past the interval.
- **[Verified · automated]** `ConnectionCoordinatorTests` (12): starts
  disconnected; `disconnected→discovering` on `startSession()`;
  `discovering→connecting`; `connecting→connected` (exposes device name);
  `connected→disconnected` path; deliberate disconnect stops the transport;
  **deliberate disconnect does not immediately reconnect**; `startSession()`
  re-arms after a disconnect; packets flow to `LocationStore` (not the
  coordinator); deliberate disconnect resets the store signal; pure phase
  mapping; **known-device state is independent of connection state**.
- **[Verified · automated]** `KnownDeviceStoreTests` (7): starts empty, remember
  adds, remember is idempotent by id, forget removes, multiple devices,
  `forgetAll`, persists across store instances.
- **[Verified · automated]** `ConnectionSetupViewTests` (5): the `Display` state →
  screen mapping — `disconnected` offers *search* with no spinner; `discovering`
  and `connecting` show a spinner and offer *Disconnect*; `connected` offers no
  action; every state has status text.
- **[Verified · simulator]** `ConnectionSetupView` rendered on the iPad simulator
  in the `discovering` state, in both **portrait and landscape** (content stays
  centred and width-capped, nothing clipped), and on iPhone portrait.
- **[Verified · automated]** `MapCameraStateTests` + `MapViewModelTests` (7):
  default heading is `nil`, `following` re-centres and keeps zoom, negative
  heading → `nil`, zero heading kept, default provider is `.googleMaps`,
  `update(with:)` moves the camera, `update(with: nil)` is a no-op.
- **[Verified · on device / simulator]** Dash builds, launches, initialises the
  Google Maps SDK (v11.1.0) with the configured key, and renders the map with the
  vehicle marker. Before any packet arrives the camera sits at
  `MapCameraState.default` (lat 0 / lon 0).

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

### Automated test totals (all passing, 2026-09-01)

| Suite | Tests | Runner |
|---|---:|---|
| `DashSharedTests` | 4 | `swift test` |
| `DashRelayTests` | 25 | `xcodebuild ... -scheme DashRelay` (iOS Simulator) |
| `DashTests` | 54 (incl. 1 no-op scaffold) | `xcodebuild ... -scheme Dash` (iOS Simulator) |

`DashRelayTests` breakdown: `LocationTrackerTests` (7), `LocationBroadcasterTests`
(5), `RelaySessionControllerTests` (8), `RelayStatusViewTests` (5).

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
- **Google Maps SDK:** `github.com/googlemaps/ios-maps-sdk`, pinned to **11.1.0**
  in `Package.resolved`, linked to the **Dash target only**.

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

5. **Multi-instance Bonjour picker deferred.** The spec wants a "Connect to:
   [device]" picker when several relays are visible. For now `LocationReceiver`
   connects to the first discovered endpoint and exposes `discoveredServiceCount`;
   a `NOTE` in the code marks where the picker goes. (Pairing/forgetting is a
   planned milestone — see §8.)

6. **Map abstraction shape.** `MapProvider` is `@MainActor` and returns a
   type-erased `AnyView` (`makeMapView(camera:) -> AnyView`) so providers can be
   held as `any MapProvider` and swapped at runtime from a future Settings
   toggle. The spec's fuller protocol (`search`, `route`, `draw`) is intentionally
   **not** on the protocol yet — display only.

7. **`MapCameraState` is a bespoke SDK-neutral value type** (plain `Double`s, no
   `CLLocationCoordinate2D`) rather than the spec's `CLLocationCoordinate2D`
   signature, to keep the boundary trivially testable and import-free.

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

15. **Pairing = known-device storage now, pairing *flow* later.** `KnownDeviceStore`
    persists a list of `KnownRelay` (by Bonjour service name) and is fully tested,
    but nothing yet decides when to add a device, offers a "Forget" action, or
    restricts connections to known devices. `KnownDeviceStore` and
    `ConnectionCoordinator` are deliberately decoupled;
    `ConnectionCoordinator.connectedDeviceName` is the bridge for later.

16. **`ConnectionState` is its own enum**, not a re-export of
    `LocationReceiver.Status.Phase`. The transport phase is a networking detail;
    the rest of the app depends on the stable `disconnected / discovering /
    connecting / connected` vocabulary the spec's requirements used.

17. **The connection/setup screen is presentational.** `ConnectionSetupView`
    takes a `ConnectionState` + action closures rather than reading
    `ConnectionCoordinator` from the environment. `RootView` is the container that
    reads the single source and wires the actions. This keeps connection state
    un-duplicated and makes the screen previewable/testable in any state
    (`ConnectionSetupView.Display`). The dashboard falls back to the setup screen
    on *any* non-connected state — including a brief incidental drop. Keeping the
    dashboard visible with a "signal lost" overlay during short reconnects is a
    deliberate later refinement (spec §3.7 / §4), not done here.

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
- **Connection UI is minimal and not designed.** `ConnectionSetupView` covers
  *not connected / discovering / connecting* with a Disconnect (or Search)
  action, but the visuals are deliberately plain and there is no "GPS signal
  lost" overlay on the dashboard, no device chooser, and the dashboard is torn
  down on any brief drop (see decision 17).
- **Pairing is storage-only.** `KnownDeviceStore` persists known devices and is
  tested, but there is no pairing flow, no "Forget" affordance, no pairing
  controls in `ConnectionSetupView`, and `LocationReceiver` still connects to the
  **first** relay it discovers regardless of what's remembered. A multi-relay
  picker is still needed.
- **`MapViewModel.swift` has 2 build warnings** (pre-existing, unrelated to this
  layer): `main actor-isolated static property 'default' can not be referenced
  from a nonisolated context` at lines 24 and 28 — the `camera: MapCameraState
  = .default` default argument. The build still succeeds. Fix belongs with a
  Map-focused change (e.g. a convenience initializer, as `MapViewModel`'s
  `provider:` default already uses).
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
- **[Planned]** Device **pairing flow** — the storage exists (`KnownDeviceStore`);
  still needed: deciding when to remember a device (pair-on-connect or an explicit
  step), a multi-relay picker in/above `LocationReceiver` (it still auto-takes the
  first result), a "Forget" affordance, and optionally restricting connections to
  known devices.
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
- **[Planned]** Map layer depth: `search` (Places API) and, later,
  `route`/`draw` (Directions/Routes, call-once-per-trip) — extend `MapProvider`.
- **[Planned]** Dock-style row of favourite/frequent destinations.
- **[Future idea]** Weather widget (WeatherKit free tier).
- **[Future idea]** Parking-location auto-pin on Bluetooth disconnect.
- **[Future idea]** Voice control (SiriKit / App Shortcuts / Speech).
- **[Future idea]** Incoming-call handling (possibly free via Continuity).

---

## 8. Next planned milestones

Roughly in order (adapts the spec §11 build order to where we are):

1. **Connection UI, continued.** First cut is done (`ConnectionSetupView` +
   `RootView` gate). Remaining: a "GPS signal lost" overlay driven by
   `LocationStore.signal`, keep the dashboard visible during brief incidental
   drops (only fall back to setup after a sustained/deliberate disconnect), and a
   designed visual pass.
2. **Pairing flow.** Multi-relay picker (above/inside `LocationReceiver`), decide
   when to `KnownDeviceStore.remember(...)` (using
   `ConnectionCoordinator.connectedDeviceName`), a "Forget" action, optionally
   filter connections to known devices.
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
  (invoked from `DashApp.init()` and the `ContentView` preview).
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

### Google Maps cost discipline (spec §5, relevant once search/routes land)

- Maps SDK map view: free/unlimited. Places (search): free ≤ 10k calls/month.
- Directions/Routes: billed **per request** — call once per trip, never on a
  timer; track against the cached route locally.

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
| *(working tree, uncommitted)* | **first DashRelay connection/status UI** — `RelayStatusScreen` (container, reads `RelaySessionController`) + `RelayStatusView` (presentational, `State` + `onStart`/`onDisconnect` closures) in a new `DashRelay/Features/Status/` folder. Startup/waiting screen (`stopped` → Start; `waiting` → "Ready to Connect" + spinner) and a connected screen (`connected` → Disconnect, wired to the existing `RelaySessionController.stop()`). Connected screen shows a **generic** message — no device name, because the session layer does not expose a client name. `DashRelayApp` root swapped to `RelayStatusScreen`; `DashRelay/ContentView.swift` scaffold removed. New `RelayStatusViewTests` (5). `waiting` state rendered on the iPhone simulator, portrait + landscape. No pairing controls. |
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
  vehicle marker, SDK authenticated with the configured key).
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
