# CLAUDE.md

Guidance for Claude Code working in this repository.

The authoritative requirements live in `PROJECT_SPEC.pdf` at the repo root
("iPad CarPlay-style Dashboard — Project Spec"). This file summarizes it for
day-to-day work. **If anything here conflicts with the spec, the spec wins** —
and do not add requirements that are not in the spec.

---

## What Dash is

A personal-use, sideloaded infotainment system for a 2019 Honda Amaze that has
no factory touchscreen or CarPlay. A WiFi-only iPad (no cellular, no GPS chip)
is mounted on the dashboard and runs a custom SwiftUI app that visually mimics
Apple CarPlay: large touch-friendly tiles, dark automotive theme, no visible
iPadOS chrome. GPS is sourced from the driver's iPhone over the local network.

Key facts from the spec:

- **Not** the real CarPlay framework (that needs OEM head-unit hardware). This
  is a normal app styled to look like CarPlay.
- Single developer, single user. Sideloaded via a paid Apple Developer account
  ($99/yr, already in place — profiles are valid for a year). **No App Store
  distribution.**
- The embedded map must be **fully interactive** (an embedded map SDK), not a
  mirrored or video-streamed view.
- Music must search the **full Apple Music catalog** via MusicKit, not just the
  local library.
- Internet (iPhone Personal Hotspot) and auto-launch on car Bluetooth connect
  (iOS Shortcuts automation) are **already solved and out of scope** for the app.

### Rejected approaches (do not revisit)

- ReplayKit screen-mirroring of Google Maps from the iPhone — one-way video
  only, no touch control, adds latency. Use an embedded map SDK instead.
- Forcing two stock apps into split view — no public API. Build map + music
  natively into one app.
- External Bluetooth GPS receiver — rejected by user preference. Use the
  companion-app GPS relay.

---

## Two-app architecture

Two separate apps, one per device, talking over the existing Personal Hotspot
LAN. The **iPhone is the server**, the **iPad is the client**. The iPad finds
the iPhone via **Bonjour service discovery — never a hardcoded IP.**

```
iPhone — DashRelay (background)          iPad — Dash (foreground UI)
  LocationTracker (CLLocationManager)      LocationReceiver (NWBrowser/NWConnection)
        │                                        │
        ▼                                        ▼
  LocationBroadcaster ──── JSON over ──────▶  LocationStore  (single source of truth)
  (NWListener + Bonjour)   hotspot LAN            │
                                                 ▼
                                          Feature views (map, music, speedometer)
```

### `DashRelay` — iPhone companion app

Purpose: read GPS/speed from the iPhone's real GPS chip and stream it to the
iPad continuously, **including while backgrounded / screen locked**.

Intended structure (spec §3):

```
DashRelay/
├── DashRelayApp.swift
├── Info.plist                       # Background Modes: "Location updates"
├── Services/
│   ├── LocationTracker.swift        # wraps CLLocationManager
│   └── LocationBroadcaster.swift    # NWListener server, advertised via Bonjour, sends JSON
├── Models/
│   └── LocationPacket.swift         # from the shared package (see DashShared)
└── Views/
    └── StatusView.swift             # minimal: "Relay active" + last-sent timestamp
```

**Background reliability (spec §3 — treat as hard requirements):**

1. Request `NSLocationAlwaysAndWhenInUseUsageDescription` (Always, not
   "While Using").
2. Enable the **"Location updates" Background Mode** capability in Xcode
   (Signing & Capabilities).
3. On `CLLocationManager`: `allowsBackgroundLocationUpdates = true` and
   `pausesLocationUpdatesAutomatically = false` (so iOS doesn't auto-pause at
   red lights).
4. Send the network packet **inside the `didUpdateLocations` callback itself** —
   no separate background timer (iOS suspends those). Each GPS fix drives one
   network send.
5. The persistent blue/green background-location indicator is expected and
   cannot be hidden — it doubles as an "is it running" check.
6. Never force-quit DashRelay from the App Switcher — iOS treats that as an
   explicit stop and it will not auto-restart. Normal backgrounding is fine.
7. Assume the phone is plugged into a charger in the car (continuous GPS +
   networking drains it).

### `Dash` — iPad dashboard app

Purpose: the UI the driver sees and touches. Owns the CarPlay-style visual layer
and all embedded features.

Intended structure (spec §4):

```
Dash/
├── DashApp.swift                    # app entry, sets up the shared LocationStore
├── Core/
│   ├── LocationStore.swift          # ObservableObject; @Published currentLocation / speed / heading
│   ├── LocationReceiver.swift       # NWBrowser discovers "_dashrelay._tcp", NWConnection consumes it
│   └── ThemeManager.swift           # dark/light switch by time of day (sunrise/sunset from location)
├── Models/
│   ├── LocationPacket.swift         # from the shared package; must match DashRelay exactly
│   └── TripStats.swift              # distance, duration, avg/max speed for the current drive
├── Features/
│   ├── Map/
│   │   ├── MapView.swift
│   │   ├── MapViewModel.swift       # consumes LocationStore, drives the active MapProvider
│   │   └── MapProvider.swift        # protocol — see "Map layer" below
│   ├── Music/
│   │   ├── MusicPlayerView.swift
│   │   └── MusicPlayerViewModel.swift   # MusicKit catalog search + playback
│   ├── Speedometer/
│   │   ├── SpeedometerView.swift        # big numeral / gauge, smoothed
│   │   └── TripComputerViewModel.swift  # derives TripStats from LocationStore over time
│   └── Settings/
│       ├── SettingsView.swift
│       └── SettingsStore.swift          # map-provider toggle, persisted via UserDefaults
└── Home/
    └── DashboardView.swift          # top-level CarPlay-style tile layout; assembles every feature
```

---

## `DashShared` — local Swift package

`LocationPacket` (the wire format: `lat, lng, speed, heading, timestamp`,
`Codable`) must live in a **small local Swift package imported by both Xcode
projects**, so the sender and receiver formats can never silently drift
(spec §4 "Shared model code", §11 step 1).

- Any type that crosses the wire goes in `DashShared`, not copied into each app.
- Both `Dash` and `DashRelay` depend on `DashShared`.
- When changing the wire format, change it once in `DashShared` and rebuild both
  apps.

---

## Single-source-of-truth: `LocationStore`

**The one architectural rule to protect (spec §2):**

> The iPad's `LocationStore` is the only thing that receives network data.
> Every feature (map, speedometer, trip computer) reads from it. **No feature
> talks to the network layer directly.**

- `LocationReceiver` owns all `NWBrowser` / `NWConnection` code and pushes
  decoded packets into `LocationStore`.
- `LocationStore` is an `ObservableObject` with `@Published` location / speed /
  heading, created once in `DashApp` and injected into the view tree.
- `MapViewModel`, `TripComputerViewModel`, `SpeedometerView`, etc. observe
  `LocationStore` only. If a new feature needs GPS data, it reads `LocationStore`
  — it does not open its own connection.

### Watchdog (spec §3.7)

`LocationStore` / the UI must detect stale data: if no packet has arrived in
~5–10 seconds, show a **"GPS signal lost"** indicator rather than freezing on
stale values. Reconnection (below) fills the gap underneath.

---

## Bonjour networking design

Discovery by service name/type, **never a hardcoded IP** — this is deliberate so
the system survives a different phone/network later (spec §2 design note).

- **Service type:** `_dashrelay._tcp` (used verbatim by both apps).
- **DashRelay (server):** `NWListener(using: .tcp)`, then
  `listener.service = NWListener.Service(name: "DashRelay", type: "_dashrelay._tcp")`.
- **Dash (client):** `NWBrowser(for: .bonjour(type: "_dashrelay._tcp", domain: nil), using: .tcp)`,
  then an `NWConnection` to the discovered instance.

**Info.plist — required in *both* apps:**

- `NSLocalNetworkUsageDescription` — user-facing reason for local network
  access (iOS prompts on first launch).
- `NSBonjourServices` — array containing `_dashrelay._tcp`; the string must
  match on both sides.

**Multiple discovered instances (spec §4):** don't silently pick one. Show a
simple picker ("Connect to: [device name]") the first time, then remember the
choice (e.g. by Bonjour service name) so later reconnects are automatic.

**Reconnection (spec §4):** treat disconnects as normal, not exceptional (phone
leaves Bluetooth range, app backgrounded further than expected, etc.).
`LocationReceiver` re-browses and reconnects on its own — the user never has to
relaunch anything. The watchdog covers the UI gap while it reconnects.

---

## Feature areas

| Area | Notes (from spec) |
|---|---|
| **Map** (§5) | Dual-provider behind a `MapProvider` protocol. `GoogleMapsProvider` (Google Maps SDK + Places + Directions/Routes — recommended primary, better India road/POI data) and `AppleMapsProvider` (MapKit — free, no key, offline-friendly fallback). `SettingsStore` picks the active one. **One provider per session — never mix data from both** (incompatible coordinate systems / POI IDs). `MapViewModel` depends only on the protocol. |
| **Music** (§6) | `import MusicKit`. `MusicAuthorization.request()`; full playback needs an active Apple Music subscription. `MusicCatalogSearchRequest` is the primary search (whole catalog, not just library). Fully custom player UI (play/pause/skip/queue/artwork) driven by MusicKit playback APIs — **no deep-linking into the stock Music app.** |
| **Speedometer + trip computer** (§7) | No new data source — both derived from the `LocationPacket` stream. Speed: `CLLocation.speed` m/s → km/h, lightly smoothed with a rolling average of the last 2–3 readings. Heading: `CLLocation.course`, optional secondary display. Trip computer: running distance, elapsed time, avg speed, max speed in `TripComputerViewModel`, **reset on Bluetooth connect** (new drive). |
| **CarPlay-style visual layer** (§8) | Dark high-contrast theme by default; `ThemeManager` auto-switches light/dark by time of day (compute sunrise/sunset from current location). Large glanceable tiles, no small text, no dense menus — design for glances while driving. Hide iPadOS chrome: full-screen, `UIApplication.shared.isIdleTimerDisabled = true` while active, no nav bars, no default list styling. Dock-style row of favorite/frequent destinations for one-tap navigation. |
| **Settings** (§5) | Map-provider toggle, persisted via `UserDefaults` in `SettingsStore`. |

### `DashboardView` is the only layout owner (spec §8)

`Home/DashboardView.swift` is the single place that assembles Map + Music +
Speedometer into the CarPlay-like grid. Individual feature views must not know
about the overall layout.

### Nice-to-haves — future only, not v1 (spec §9)

Weather widget (WeatherKit free tier), parking-location auto-pin on Bluetooth
disconnect, voice control (SiriKit / App Shortcuts / Speech), incoming-call
handling. Do not build these before v1 is done.

---

## Google Maps cost discipline (spec §5)

Single personal user — stays in free tier if you follow these:

- Maps SDK map view: free, unlimited — fine to show for hours.
- Places API (search): free to 10,000 calls/month.
- **Directions/Routes API: billed per request. Call it once per trip, not on a
  timer.** ~60–90 trips/month is within free tier.
- No continuous re-routing timers. Track position against the cached route
  locally (free); only re-call Directions when actually off-route.
- Set a Google Cloud billing budget alert (~$1) as a safety net.

---

## Coding & architecture principles

- **SwiftUI + MVVM.** Feature views pair with a `...ViewModel` / `...Store`;
  views stay declarative, logic lives in the model layer (matches the spec's
  file layout).
- **One source of truth for GPS:** `LocationStore` (see above). Non-negotiable.
- **Depend on protocols at feature boundaries**, not concrete SDK types —
  `MapViewModel` uses `MapProvider`, never `GMSMapView` / `MKMapView` directly.
- **Shared wire types live in `DashShared`**, never duplicated per app.
- `DashboardView` owns layout; feature views don't.
- Disconnects and stale data are normal operating states — handle them in the
  UI (watchdog + auto-reconnect), don't treat them as errors to surface.
- Keep DashRelay's UI minimal — its job is the background relay, not a screen.

---

## Testing expectations

The spec does not define a formal test plan, so keep tests proportionate and
focused on the parts most likely to break silently:

- **`LocationPacket` encode/decode round-trip** in `DashShared` — this is the
  contract between the two apps; a drift here breaks everything.
- **Trip computer math** — distance accumulation, avg/max speed, reset-on-new-
  drive — is pure logic derived from a packet stream and should be unit-tested
  with synthetic sequences.
- **Speed smoothing** (rolling average, m/s → km/h) — pure and testable.
- **Watchdog / staleness logic** — "no packet for N seconds ⇒ signal lost".
- Networking (`NWListener` / `NWBrowser`) and MusicKit / Maps SDK integration
  are validated on-device, not in unit tests.

Test setup in this project:

- Unit tests: **Swift Testing** (`import Testing`, `@Test`, `#expect`) — see
  `DashTests/`.
- UI tests: **XCTest** — see `DashUITests/`.

---

## Constraints from the spec (quick reference)

- Personal use only; sideloaded; no App Store. Paid developer account already
  set up (1-year profiles).
- iPad has **no GPS chip and no cellular** — all location data comes from
  DashRelay over the LAN.
- **No hardcoded IPs** — Bonjour discovery from the start.
- Real interactive map SDK — no screen mirroring / video streaming.
- Full Apple Music catalog via MusicKit — not just the local library; custom
  player UI, no deep links to the stock app.
- One map provider active per session; never mix Google + Apple data.
- Directions API is call-once-per-trip; no routing timers.
- DashRelay must survive backgrounding — Always location auth, Location Updates
  background mode, send on `didUpdateLocations`, never force-quit.
- Assume the phone is charging in the car.

---

## Recommended build order (spec §11)

1. **`LocationPacket` shared package + DashRelay's `LocationTracker` /
   `LocationBroadcaster`** — background-reliable GPS relay. Everything depends on
   this working first.
2. **`LocationReceiver` + `LocationStore` on the iPad**, with the stale-data
   watchdog.
3. **`DashboardView` skeleton with placeholder tiles** — validate the
   CarPlay-style layout early.
4. **`MapProvider` abstraction + `GoogleMapsProvider`**, wired to
   `LocationStore`.
5. **`MusicPlayerViewModel`** — MusicKit catalog search + playback.
6. **`SpeedometerView` + `TripComputerViewModel`.**
7. **`AppleMapsProvider`** as the second provider + settings toggle.
8. **Polish pass:** theming, idle-timer disable, dock/favorites row.

---

## Current repository state (2026-09-02)

**`PROJECT_STATUS.md` at the repo root is the authoritative, always-current
status.** Read it before starting work — this section is only a pointer.

Built and committed so far (latest commit `973ffc9 feat(map): add destination
search`):

- **`DashShared` package** — `LocationPacket`, `LocationWireFormat`,
  `RelayAdvertisement`. Imported by `Dash` and `DashRelay`.
- **`DashRelay` (iPhone)** — `LocationTracker`, `LocationBroadcaster` (Bonjour +
  TXT record), `RelayIdentity`, `RelaySessionController`, and a minimal
  `RelayStatusView`. GPS relay confirmed working device-to-device.
- **`Dash` (iPad)** — `LocationReceiver` / `PacketLineBuffer` /
  `LocationStore` (single source of truth + staleness watchdog);
  `ConnectionCoordinator` + `KnownDeviceStore` (session + pairing);
  `RootView` connection gate with `ConnectionSetupView` / `ConnectedControlView`.
- **Map** — `MapProvider` rendering-only protocol with `GoogleMapProvider`
  (Google Maps SDK 11.1.0); SDK-neutral `MapContent` / `MapEvent` / `MapMode` /
  `MapGeometry` / `MapCameraState`; `MapViewModel` fed from `LocationStore`.
- **Destination search (M2)** — `PlaceSearchService` protocol (separate from
  `MapProvider`) with `GooglePlaceSearchService` (Google Places SDK 11.1.0,
  autocomplete + Place Details New); SDK-neutral `Destination` /
  `PlaceSuggestion` / `DestinationStore` / `PlaceSearchViewModel`; custom
  `MapSearchView`; `MapViewModel.setDestination(_:)` drops a pin and frames a
  vehicle-plus-destination preview camera.
- Single `Dash.xcodeproj` (kept, not a workspace) with 6 targets; `DashShared`
  is a local SPM package referenced by the project. Bundle ids
  `com.sakshamsharma.Dash` / `.DashRelay`, team `LGQX79QMNJ`, apps target
  iOS 18.6, test bundles 26.5.

Not yet built: `Home/DashboardView` (the CarPlay tile layout — `ContentView` is
still a placeholder full-screen map + search overlay), `ThemeManager`, music,
speedometer/trip computer, `AppleMapProvider` + settings toggle, routing /
navigation. See `PROJECT_STATUS.md` §7–§8 for the full list and ordering.

---

## Working agreements for Claude Code

- Do not modify the Xcode project or implement features unless the current task
  asks for it.
- Re-read the relevant `PROJECT_SPEC.pdf` section before building a feature area;
  don't rely on this summary alone for details.
- Don't invent requirements. If the spec is silent on something, ask or flag it
  rather than assuming.
