# binnacle-connect

Binnacle Connect — the phone and cloud companion app for Vision/Track, and
its web dashboard/marketing site.

## What's in this repo

- `flutter_app/` — the Connect mobile app. Flutter/Dart, per the decided
  architecture in `Binnacle_Connect_App_Architecture_Flutter_Spec`.
- `web_dashboard/` — a separate React/Vite web dashboard and marketing site.
- `tools/connect_audit/` — a static policy auditor for `flutter_app/`, plus
  its regression fixtures and self-test.
- `.github/workflows/ci.yml` — runs `dart analyze`, `flutter test`,
  `flutter build web`, the static auditor, and the web dashboard build on
  every push and pull request.

## What's deliberately NOT in this repo

Business, legal, and program-management documents — the Charter, the Fork
Tracker, contest rules, consent/BIPA design, moderation design, live
broadcast terms — stay in Google Drive under `Engineering/Connect`. This
repo is code only. If you're looking for why a design decision was made,
check Drive first; the code comments cross-reference the relevant documents
by name but don't restate them.

## Status, stated honestly

As of this import:

- `dart analyze`: clean (0 errors; ~20 info-level style lints, all
  `prefer_const_constructors` or one known false-positive-shaped
  `use_build_context_synchronously`).
- `flutter test`: 3/3 passing — app launch, navigation, and the simulated
  link-status badge.
- `flutter build web`: succeeds; compiled output verified to contain real
  app logic (not a stub).
- `connect_audit.py`: passes clean against `flutter_app/lib`.
- **Nobody has looked at a rendered screen.** No visual QA has happened.
  This is the one thing only a human can do — see "Running it locally"
  below.
- No Android or iOS build has been attempted (no SDK/Xcode were available
  where this was built). Web is the only verified target so far.
- No connection to real hardware exists yet. Every screen runs on
  `LinkStatus.simulated`. Vision hardware has not been built (see the Fork
  Tracker in Drive — VIS-01 camera procurement is still open).

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
