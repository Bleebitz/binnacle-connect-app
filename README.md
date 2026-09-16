# binnacle-connect

Binnacle Connect — the phone and cloud companion app for Vision/Track, and
its web dashboard/marketing site.

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
  `flutter build web`, the static auditor, and the web dashboard build on
  every push and pull request. It does not yet build the Android APK — see
  "What's still missing" below; this repo also has no configured git
  remote, so this workflow file exists but has never actually run in CI.

## Toolchain

Verified against **Flutter 3.41.4 (Dart 3.11.1)**, `flutter doctor` clean,
on Windows with the Android SDK (platform 36.1, build-tools 36.1.0)
installed and licensed. No version manager (FVM etc.) is in use — this is
a single-developer local project so far; if it grows a second machine or a
CI runner, pin the toolchain properly at that point rather than assuming
"whatever's on PATH" stays consistent. Until then, if something behaves
differently on your machine, check your `flutter --version` against the
one above first.

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

## What's deliberately NOT in this repo

Business, legal, and program-management documents — the Charter, the Fork
Tracker, contest rules, consent/BIPA design, moderation design, live
broadcast terms — stay in Google Drive under `Engineering/Connect`. This
repo is code only. If you're looking for why a design decision was made,
check Drive first; the code comments cross-reference the relevant documents
by name but don't restate them.

## Status, stated honestly

- `dart analyze`: clean (0 errors; info-level style lints only, all
  `prefer_const_constructors` or one known false-positive-shaped
  `use_build_context_synchronously`).
- `flutter test`: 7/7 passing — app launch, navigation, the simulated
  link-status badge, and Compete's three leaderboards (King of Wake, Top
  Tricks, Best Falls) plus the Riders aggregate.
- `flutter build web`: succeeds; compiled output verified to contain real
  app logic (not a stub). Rendered and interacted with in a real browser —
  every screen, not just Capture — including tapping through the Compete
  leaderboards, favoriting a Library clip, and triggering/dismissing the
  MOB alert.
- `flutter build apk --debug`: succeeds, and the APK has been installed and
  launched on an Android emulator (API 36) — confirmed rendering correctly
  (including the demo-mode `Simulated` status) and confirmed basic tab
  navigation works without crashing. Not yet tried on a physical device or
  as a release build.
- `connect_audit.py`: passes clean against `flutter_app/lib`.
- No iOS build has been attempted (no Xcode available where this was
  built).
- No connection to real hardware exists yet. Demo mode (the default —
  see "App mode" above) never attempts one on purpose. Vision hardware has
  not been built (see the Fork Tracker in Drive — VIS-01 camera procurement
  is still open), so core mode is wired but unverified against anything
  real.

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
