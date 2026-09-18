# binnacle-connect

Binnacle Connect — the phone and cloud companion app for Vision/Track, and
its web dashboard/marketing site.

## BIN-32 implementation checkpoint — 2026-09-15

Started from inspected `main` at `3916e7c`, preserving its My Boat / Live /
Session / Library / Community navigation and all Community/Compete source.
Connect owns phone/cloud software and the operator interface; Spotter is
physical display hardware, governed by approved Charter Amendment 1 v2.

Two controlled increments on `bin-32/live-core-boundaries`:

1. Core mode starts offline with unknown readiness, an empty Library, no
   demo camera scene and no fabricated telemetry readout. Demo media import,
   capture creation and pairing helpers reject Core-mode calls. Community
   remains usable in Demo and is explicitly sequenced behind live integration
   in Core mode. Removed the hard-coded compute model. Capture waits for a
   matching acknowledgment, distinguishes rejection/timeout/disconnect, and
   never inserts fabricated Core clips. Even an acknowledgment is described
   as acknowledgment, not proof that playable media exists.
2. Socket lifecycle closes prior subscriptions/timers, applies 1/2/4/8/16/32s
   reconnect backoff, has a 10s initial-state deadline, ignores old-connection
   callbacks and non-increasing state sequences, and cancels pending commands
   on lost links. Unpairing/credential replacement closes the old connection;
   expired credentials fail closed. Commands are never replayed. Credential
   device/host matching and encrypted transport are required (loopback-only
   plain WebSocket is permitted for automated tests).

Client tests use the existing provisional `topic/payload` envelope. A capture
acknowledgment must contain its matching `id` and a boolean `ok`; missing or
malformed outcomes are not success. This acknowledgment wire shape is a
client integration assumption, NOT a verified firmware contract. The socket
path and query-token authentication inherited from the scaffold still require
Core contract/security review before real deployment.

Verification for these increments:

- Flutter 3.41.4 / Dart 3.11.1, matching `.fvmrc`.
- 15 tests pass (7 retained UI tests and 8 service/socket tests). The Core-mode
  widget test is intentionally skipped in the default Demo run; run it separately:
  `flutter test test/live_mode_test.dart --dart-define=BINNACLE_APP_MODE=core --dart-define=BINNACLE_CORE_URL=https://core.invalid`.
  That separate test passes and is now included in CI.
- `dart analyze`: exit 0, no errors/warnings; 44 info-level style findings.
- Static policy audit: no findings (Windows needs `PYTHONUTF8=1`).
- Core-mode web build passed after both increments. Build warnings mention
  optional Cupertino font assets; no web build failure.
- Android release build reached Gradle/CMake configuration but the managed
  Windows environment could not execute the installed NDK `clang.exe`; no APK
  was produced. This is recorded as an environment-blocked check, not release
  or physical-device acceptance.
- Lockfile reconciled to the pinned Flutter SDK's dependency constraints.

**Update (see "Status, stated honestly" below for the current, complete
picture):** every item this section originally listed as still open — real
pairing transport, QR camera scanning, hardware-backed (software-generated,
Keychain/Keystore-persisted — not Secure-Enclave-bound) key generation,
secure credential persistence, authenticated WebRTC, Core media catalog and
actual Library playback/download/share — is now implemented client-side.
The Android release-build environment block below is also resolved. What
genuinely remains: an approved Core wire contract (this client's endpoint/
framing assumptions throughout are still unverified against a live Core —
none exists yet) and the physical acceptance sequence on real hardware.
INTERNET permission was already in the release manifest at the inspected
baseline; that alone does not establish Android release-network acceptance.

Physical acceptance must record device/firmware/app revisions and demonstrate
pair → authenticated connection → live telemetry/video → rider/Track state →
capture acknowledgment → actual Library playback. Include unauthorized/expired
credentials, certificate mismatch, AP restart, phone sleep/resume, Internet-off
LAN operation, link loss, rejection and timeout. No simulated result closes
this gate. The historical status section below describes the prior baseline.

## What's in this repo

- `flutter_app/` — the Connect mobile app. Flutter/Dart, per the decided
  architecture in `Binnacle_Connect_App_Architecture_Flutter_Spec`. Ships
  with generated `web/` and `android/` runners (both committed — see
  Toolchain below); iOS/macOS/Windows/Linux runners are deliberately not
  generated yet, to avoid maintaining platforms nobody is building for.
- `web_dashboard/` — a separate React/Vite web dashboard and marketing site.
- `tools/connect_audit/` — a static policy auditor for `flutter_app/`, plus
  its regression fixtures and self-test.
- `.github/workflows/ci.yml` — runs `dart analyze`, `flutter test`,
  `flutter build web`, `flutter build apk --debug`, the static auditor, and
  the web dashboard build on every push and pull request against
  [github.com/Bleebitz/binnacle-connect-app](https://github.com/Bleebitz/binnacle-connect-app)
  — [first green run](https://github.com/Bleebitz/binnacle-connect-app/actions/runs/35048699219).
  The web bundle and debug APK are uploaded as workflow artifacts.

## Toolchain

Pinned to **Flutter 3.41.4 (Dart 3.11.1)** — see `flutter_app/.fvmrc`,
which is the single source of truth this repo's CI workflow is kept in
sync with by hand (`subosito/flutter-action`'s `flutter-version:` doesn't
read `.fvmrc` automatically; if you bump one, bump the other). Verified
with `flutter doctor` clean on Windows with the Android SDK (platform
36.1, build-tools 36.1.0) installed and licensed. FVM itself isn't
installed/required locally — `.fvmrc` exists as the pinned-version record
CI and contributors check against, not as a mandatory tool dependency.

## App mode: demo vs. core

The app has exactly two modes, chosen at build/run time via `--dart-define`
— never a runtime toggle, so a demo build can't drift into talking to a
real Core and a Core build can't silently fall back to fake data:

- **`demo`** (the default if you pass nothing) — opens no network
  connection at all. Every screen shows an honest `Simulated` link status
  permanently. This is what you want for a local demo or screenshots.
- **`core`** — requires `BINNACLE_CORE_URL` (e.g.
  `https://your-core-host`). Omitting it is treated as a broken deploy: the
  app refuses to start and shows a configuration-error screen instead of
  quietly running in demo mode. There is no real Core to point this at yet
  (see "No connection to real hardware exists yet" below) — this mode
  exists so the wiring is correct in advance, not because it's usable today.

See `flutter_app/lib/core/app_config.dart` for the exact contract.

### Demo camera feed

The Live tab uses one camera-media boundary for both modes. Demo builds select
the bundled `assets/demo/gopro_dev_footage.mp4` recording; Core builds select
the authenticated WebRTC service. Both render inside the same 16:9,
center-cropped viewport with the same HUD layer.

Demo playback autostarts, loops, and drives a deterministic Vision/Track HUD
timeline from video position (acquiring → rider locked → tracking → the real
fall/loss window → reacquiring). It is always labeled
`DEMO — RECORDED CAMERA FEED`. Digital **Zoom**, **Snapshot**, and
**Save Highlight** work locally on the recorded feed: zoom is a presentation
change of the video, Snapshot saves a real frame of the recording at the current
playback position, and Save Highlight saves a start/end reference into the
bundled asset (no video is copied). Local Demo media is tagged , persists
across restarts, and is never presented as Core-captured. Presets, orientation,
trigger mode, arm/disarm, and broadcast remain disabled, and no Core command is
sent, so the demo cannot imply or send a hardware action. See
 for the revision and its limits.
The bundled asset is a
130-second, fixed-stern GoPro rider pass trimmed from owner-supplied
`GX010048.MP4`, normalized to a 1920×1080 H.264 High 4:2:0 MP4, and stripped
of audio for demo playback.

## Product structure

Bottom nav is **My Boat / Live / Session / Library / Community** — reorganized
around the actual boating experience (connect → ride → review → share/
compete) per BIN-32, replacing an earlier Capture / Library / Crew / Compete
/ Settings layout that gave Crew and Compete the same navigational weight as
operating the camera:

- **My Boat** (`my_boat_screen.dart`) — the front door. Answers "is Binnacle
  connected, is Vision online, is Track ready, who's riding, are we
  recording, is storage/temp/network healthy" in one place, instead of that
  being scattered across other screens' status bars.
- **Live** (`capture_screen.dart`, class `CaptureScreen`) — the Vision/Track
  interface: camera feed, framing/zoom, presets, recording, save highlight,
  safety alerts. Same screen as before; renamed in the nav, not rewritten.
- **Session** (`session_screen.dart`) — a chronological day-on-the-water
  timeline (passes, highlights, falls, photos, rider changes) built from
  real `ClipRepository` data. v1 scope, stated honestly: there's no real
  session-boundary model yet (start/end tied to an arm/pairing cycle) — this
  shows every captured clip as one running timeline, which is what a single
  day actually looks like today without inventing boundaries the app can't
  detect yet.
- **Library** (`library_screen.dart`) — cinematic feed unchanged from before
  the BIN-32 reorg (see git history), but the clip data behind it is no
  longer purely decorative: Core mode fetches a real clip catalog from the
  Core (`MediaCatalogService`) and, for any clip the Core reports a real
  media URL for, plays it with `video_player`, downloads it via
  `url_launcher`, and shares it via `share_plus` — all real client
  behavior, unverified against a live Core (see "Status" below).
- **Community** (`community_screen.dart`) — Crew and the four leaderboards
  (King of Wake, Top Tricks, Best Falls, Riders), one level down instead of
  four separate top-level tabs. `CrewScreen` and `CompeteScreen` are now
  body-only widgets (no Scaffold/AppBar of their own) embedded as tabs here.

Settings is no longer a bottom-nav tab — it's behind My Boat's profile icon
(account/device management isn't a primary boating activity on the same
footing as riding, reviewing, or competing).

## What's deliberately NOT in this repo

Business, legal, and program-management documents — the Charter, the Fork
Tracker, contest rules, consent/BIPA design, moderation design, live
broadcast terms — stay in Google Drive under `Engineering/Connect`. This
repo is code only. If you're looking for why a design decision was made,
check Drive first; the code comments cross-reference the relevant documents
by name but don't restate them.

## Status, stated honestly

- `dart analyze`: clean (0 errors/warnings; info-level style lints only).
- `flutter test`: 82 passing (2 intentionally skipped), covering app launch/navigation, the
  Compete leaderboards and Riders aggregate, real pairing-transport
  HTTP behavior, real EC key generation/persistence, real secure-storage
  round-tripping, the Core-mode socket boundary (ack/reject/timeout/
  disconnect, reconnect-without-replay, bearer-token-off-the-URL), real
  WebRTC signaling over the control socket, and real Core clip-catalog
  fetch/error/retry behavior.
- `flutter build web`: succeeds in both demo and Core mode; compiled
  output verified to contain real app logic (not a stub). Rendered and
  interacted with in a real browser — every screen, not just Live —
  including tapping through Community's Compete leaderboards, favoriting a
  Library clip, viewing the Session timeline, and triggering/dismissing
  the MOB alert.
- `flutter build apk --debug`: succeeds, both locally and in CI, including
  with the real `flutter_webrtc` native plugin now compiled in. The APK
  has been installed and launched on an **Android emulator** (API 36) —
  confirmed rendering correctly (including the demo-mode `Simulated`
  status) and confirmed basic tab navigation works without crashing.
- `flutter build apk --release`: succeeds (signed with the debug key —
  no release keystore exists yet, which is itself accurate: this isn't
  ready to publish). A prior BIN-32 pass reported this environment-
  blocked by an NDK compiler that couldn't execute; that's no longer
  reproducing and it now runs in CI too.
- `connect_audit.py`: passes clean against `flutter_app/lib`, in CI too.
- No iOS build has been attempted (no Xcode available where this was
  built).
- **What's real client-side now**: pairing transport (real HTTPS),
  QR camera scanning, EC keypair generation + Keychain/Keystore-backed
  credential persistence, the Core-mode socket boundary (real ack/reject/
  timeout/reconnect, no command replay, bearer token off the URL), real
  WebRTC signaling + a genuine `RTCPeerConnection`/ICE/video-track
  lifecycle, and a real Core clip-catalog fetch feeding real playback/
  download/share.
- **What every one of those has in common**: no real Core exists to
  verify any of it against yet (VIS-01 camera procurement is still open
  per the Fork Tracker in Drive). Every wire contract above (pairing
  endpoint shape, socket auth framing, WebRTC signaling topics, clip
  catalog endpoint/fields) is this client's best-effort, documented
  assumption — real, tested client behavior on this side of that
  boundary, unverified on the other side of it. Demo mode never attempts
  any of this on purpose (see "App mode" above).
- **Still genuinely open**: an approved Core wire contract to replace
  those assumptions, and the physical acceptance sequence — pair →
  authenticated connection → live telemetry/video → rider/Track state →
  capture acknowledgment → actual Library playback, including
  unauthorized/expired credentials, certificate mismatch, AP restart,
  phone sleep/resume, Internet-off LAN operation, link loss, rejection
  and timeout. No simulated result closes that gate — it needs a real
  Core and a real device, neither of which this environment has.

## Running it locally

```bash
cd flutter_app
flutter pub get
flutter run -d chrome        # opens a real browser window, hot reload
```

Or, to build and serve the production bundle the same way CI does:

```bash
cd flutter_app
flutter build web
cd build/web
python3 -m http.server 8080
# open http://localhost:8080 — NOT the file path directly.
# Flutter's runtime fetches its compiled assets at startup; this fails
# under file:// even though the entry script itself isn't an ES module.
```

For Android (a connected device or a running emulator):

```bash
cd flutter_app
flutter pub get
flutter run                  # picks the connected device/emulator
```

Or to build the debug APK CI would build:

```bash
cd flutter_app
flutter build apk --debug
# output: build/app/outputs/flutter-apk/app-debug.apk
```

Both default to demo mode. To point at a real Core instead (see "App mode"
above — there is no real Core to point this at yet, so this is currently
untested against anything real):

```bash
flutter run --dart-define=BINNACLE_APP_MODE=core \
            --dart-define=BINNACLE_CORE_URL=https://your-core-host
```

For the web dashboard:

```bash
cd web_dashboard
npm install
npm run dev
```

## Running the static auditor

```bash
python3 tools/connect_audit/connect_audit.py flutter_app/lib
```

It checks five specific failure shapes that have actually occurred in this
codebase during development — see the module docstring in
`connect_audit.py` for what each one is and why it's there. It's a
heuristic over source text, not a real Dart AST parser: it complements
`dart analyze` and `flutter test`, it doesn't replace either.

Self-test (confirms the auditor itself still correctly blocks a known-broken
fixture and passes a known-good one):

```bash
cd tools/connect_audit
bash run_tests.sh
```
