# PROJECT_STATUS.md

Living status document for **Dash**. It describes the repository as it actually
stands so a future developer (or a fresh Claude Code session) can get oriented
without conversation history.

- **Last updated:** 2026-09-01
- **Branch:** `main`
- **Latest commit:** `54fa7e8 feat(map): add live vehicle map`
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
    │   ├── DashApp.swift            # @main; owns LocationStore (@StateObject); bootstraps Google Maps
    │   ├── ContentView.swift        # currently just a full-screen DashMapView (placeholder shell)
    │   ├── Info.plist               # NSBonjourServices, GoogleMapsAPIKey = $(GOOGLE_MAPS_API_KEY)
    │   ├── Configuration/
    │   │   └── GoogleMapsConfiguration.swift   # reads key from Info.plist, calls GMSServices.provideAPIKey
    │   ├── Core/
    │   │   ├── LocationReceiver.swift          # NWBrowser + NWConnection, reconnect loop
    │   │   ├── PacketLineBuffer.swift          # reassembles \n-delimited JSON → [LocationPacket]
    │   │   └── LocationStore.swift             # single source of truth + watchdog
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
    │   ├── MapCameraStateTests.swift
    │   └── DashTests.swift          # scaffold `example()` — no-op, still present
    ├── DashUITests/                 # Xcode scaffold only, no real tests
    └── DashRelay/                   # iPhone app target
        ├── DashRelayApp.swift       # @main; private Relay wires LocationTracker → LocationBroadcaster
        ├── ContentView.swift        # still the "Hello, world!" scaffold
        ├── Info.plist               # UIBackgroundModes:[location], NSLocalNetworkUsageDescription, NSBonjourServices
        ├── Services/
        │   ├── LocationTracker.swift       # wraps CLLocationManager, converts fixes → LocationPacket
        │   └── LocationBroadcaster.swift   # NWListener advertised via Bonjour, \n-delimited JSON to N clients
        └── DashRelayTests/
            ├── LocationTrackerTests.swift
            └── LocationBroadcasterTests.swift
```

`DashShared` is referenced by the Xcode project as a local Swift package and
linked into `Dash`, `DashTests`, `DashRelay`, and `DashRelayTests`.

### Runtime data flow (as built)

```
iPhone — DashRelay                          iPad — Dash
────────────────────                        ──────────────────
CLLocationManager
  → LocationTracker.packet(from:)           LocationReceiver (NWBrowser "_dashrelay._tcp"
  → onPacket closure (in didUpdateLocations)   → NWConnection → receive loop)
  → LocationBroadcaster.broadcast(_:)          → PacketLineBuffer.append(_:)  (split on \n, decode)
  → NWListener → all TCP clients ───JSON+\n──▶ → LocationStore.ingest(_:)   ← SINGLE SOURCE OF TRUTH
                                                 ├─ @Published latestPacket / signal / linkPhase
                                                 └─ watchdog Task: no packet in staleInterval ⇒ signal = .stale
                                                        │
                                              ContentView (observes LocationStore)
                                                → DashMapView(viewModel:, location: latestPacket)
                                                → MapViewModel.update(with:)  → camera = camera.following(packet)
                                                → GoogleMapProvider → GMSMapView.animate(to:) + move marker
```

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
- **Disconnects are routine.** `LocationReceiver` re-browses and reconnects on a
  timer; `LocationStore`'s watchdog covers the UI gap.
- **SwiftUI + MVVM**, `@MainActor` isolation, serial-queue-confined
  `@unchecked Sendable` classes for the Network-framework wrappers.

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
  inside `didUpdateLocations`.
- **[Implemented]** `LocationBroadcaster` — `NWListener` advertised as a Bonjour
  `_dashrelay._tcp` service; accepts multiple concurrent TCP clients; sends each
  packet as one `\n`-terminated JSON line; clean connect/disconnect handling; a
  main-actor `onStatusChange` hook (`isListening`, `clientCount`).
- **[Implemented]** `DashRelayApp` wires `tracker.onPacket → broadcaster.broadcast`
  and starts both at launch.
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
- **[Implemented]** DashRelay app builds and launches (SwiftUI scaffold UI only).

### Dash (iPad)

- **[Implemented]** `LocationReceiver` — `NWBrowser` for `_dashrelay._tcp`,
  connects to the first discovered endpoint, receive loop feeding
  `PacketLineBuffer`; automatic re-browse/reconnect after a delay on any
  drop/failure; `Status` phases `stopped / browsing / connecting / connected` via
  a main-actor `onStatusChange`.
- **[Implemented]** `PacketLineBuffer` — reassembles the TCP byte stream, splits
  on `\n`, decodes each line, keeps partial trailing lines, skips blank/malformed
  lines, drops the buffer if an unterminated line exceeds 64 KB.
- **[Implemented]** `LocationStore` — `@MainActor ObservableObject`, the single
  source of truth: `@Published latestPacket / signal / linkPhase`; derived
  `hasFix / isSignalLost / speed / heading`; `ingest(_:)` records a packet and
  arms the watchdog; watchdog `Task` sleeps `staleInterval` (default 7 s, in the
  spec's 5–10 s band) then flags `.stale` while keeping the last packet;
  `refreshSignal(now:)` for deterministic tests; mirrors the receiver's link
  phase; `start()/stop()` delegate networking to `LocationReceiver`.
- **[Implemented]** `DashApp` owns `LocationStore` as `@StateObject`, injects it
  as an `environmentObject`, starts it in `.task`, and calls
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
- **[Verified · automated]** `LocationStoreTests` (12): initial state, ingest
  becomes source of truth, latest-wins, live within interval, goes stale, stale
  retains packet, recovers after stale, watchdog `Task` fires on its own, wired to
  receiver callback, mirrors link phase, brief link drop keeps last-known, `stop()`
  resets.
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

### Automated test totals (all passing, 2026-09-01)

| Suite | Tests | Runner |
|---|---:|---|
| `DashSharedTests` | 4 | `swift test` |
| `DashRelayTests` | 12 | `xcodebuild ... -scheme DashRelay` (iOS Simulator) |
| `DashTests` | 32 (incl. 1 no-op scaffold) | `xcodebuild ... -scheme Dash` (iOS Simulator) |

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
  simulator to confirm the Google Maps SDK initialises and renders.
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

---

## 6. Current limitations / known issues

- **No dashboard UI.** `ContentView` is a bare full-screen map. There is no
  tile layout, no theming, no "GPS signal lost" banner surfaced to the user
  (the `LocationStore.signal` state exists but nothing displays it).
- **DashRelay has no real UI.** `ContentView.swift` is still the "Hello, world!"
  scaffold — no "Relay active" / last-sent-timestamp status screen (spec §3).
- **No connection/session lifecycle UI.** No pairing, no "forget device", no
  visible connection state, no reconnect indicator. `LocationReceiver` always
  auto-connects to the first relay it sees.
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

- **[Planned]** DashRelay `StatusView` (relay-active + last-sent timestamp).
- **[Planned]** Connection/session lifecycle: visible link state, watchdog
  "GPS signal lost" indicator in the UI, reconnect feedback.
- **[Planned]** Device pairing / "forget device" (the deferred multi-instance
  Bonjour picker + remembered choice by service name).
- **[Planned]** `Home/DashboardView` — the CarPlay-style tile layout that
  assembles map + music + speedometer (the single layout owner).
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

1. **Connection / session lifecycle.** Surface `LocationStore.signal` and
   `linkPhase` in the UI; "GPS signal lost" indicator; show reconnect state.
2. **Pairing / forgetting.** Multi-instance Bonjour picker in `LocationReceiver`,
   remember the chosen relay by Bonjour service name, "forget device" action.
3. **DashRelay `StatusView`** — minimal relay-active / last-sent-timestamp screen.
4. **`DashboardView` skeleton** — placeholder tiles to validate the CarPlay-style
   layout; move the map into a tile (retire the `ContentView` full-screen shell).
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
  devices by the developer.
- **Google Maps renders in Dash** — confirmed in the iOS Simulator (map tiles +
  vehicle marker, SDK authenticated with the configured key).
