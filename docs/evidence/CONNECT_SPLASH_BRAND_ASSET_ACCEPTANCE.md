# Connect — Branded Startup / Splash Experience: Brand Asset & Implementation Acceptance

**Task purpose:** Replace Connect's placeholder text-only launch screen with a real branded
startup/splash experience — production wave background, transparent Binnacle logo, "CONNECT"
identification, a premium fade/scale entrance animation, a genuine minimum 3.5-second display
floor, and a wait for real app readiness (not a fabricated delay) — without interfering with
auth, navigation, deep links, or Core initialization.

**Date:** 2026-09-17
**Repository:** https://github.com/Bleebitz/binnacle-connect-app
**Branch:** `add-brand-background-image` (an existing branch already carrying prior background/
splash groundwork from this work session was reused per instructions, rather than opening a new
branch)
**Source commit SHA (before this task's work):** `f420b47663d4e8c56240e5a5cb2796225d57b366`
**Final commit SHA:** see the git log for the commit this file was committed in — recorded in
the MASTER REGISTER UPDATE section of the accompanying final report, not duplicated here to
avoid it going stale if the commit is amended.
**Related Linear issues:** BIN-32 (parent)

---

## 1. BRAND ASSET PREPARATION

Both production assets were supplied directly by the user in this session (as image attachments)
rather than generated or sourced by the agent, and were saved from the user's Downloads folder
into the repository.

### 1.1 Logo

- **Source file:** `Codex Image Sep 17, 2026, 11_24_53 AM.png` (user-supplied; a Binnacle Marine
  Systems shield/compass mark with "BINNACLE MARINE SYSTEMS" wordmark)
- **Source dimensions:** 1408×1117 px, RGBA — **already fully transparent** (alpha channel
  present, background already removed at the source; verified by inspecting the alpha channel's
  bounding box before any processing)
- **Processing performed:** trimmed to the opaque-content bounding box only (`alpha.getbbox()`
  → crop `(49, 21, 1394, 1099)`), removing surrounding fully-transparent padding. **No masking,
  chroma-keying, or background-removal was required** — the source was already RGBA with a clean
  transparent background.
- **Final logo path:** `flutter_app/assets/brand/binnacle_logo.png`
- **Final logo dimensions:** 1345×1078 px, RGBA
- **Manual cleanup required:** No (beyond the trim above)

### 1.2 Wave background

- **Source file:** `Firefly_Gemini Flash_ Abstract dark UI background for a wake surfing app,
  deep oceanic navy blue and black 383138.png` (user-supplied)
- **Source dimensions:** 768×1376 px, RGB
- **Defects found in source:** (a) a fake phone status bar overlay baked into the image (clock
  "12:03", wifi/signal/battery glyphs) occupying roughly the top 48 px; (b) a semi-transparent
  "V"-shaped watermark/logo mark baked into the lower-middle portion of the image (~x 330–450,
  y 1245–1345 in source coordinates)
- **Background-removal / masking method used:**
  1. Cropped the top 48 px to remove the fake status bar entirely (verified clean by inspecting
     the resulting top edge — no residual banding).
  2. The watermark sits inside a continuous flowing wave pattern, so a donor-patch clone-stamp
     was rejected after inspection (it visibly broke the flow of the wave lines crossing that
     region). Instead, a **feathered local Gaussian blur** was composited over just that region:
     an elliptical mask covering the watermark (with a 22 px Gaussian-blurred feather for a soft
     edge) selects pixels from a 14 px-radius Gaussian-blurred copy of the same image, composited
     back over the original. This destroys the sharp geometric watermark shape while keeping the
     surrounding ambient wave texture visually continuous, with no visible seam.
  3. Result re-inspected at full resolution (both the top edge and the former watermark region)
     to confirm no residual artifacts before saving.
- **Manual cleanup required:** Yes — the watermark removal above was a manual, deliberate
  compositing step (not an automatic/library background-removal call); the status-bar crop was a
  straightforward geometric crop.
- **Final background path:** `flutter_app/assets/backgrounds/wave_glow.png` (same path as the
  pre-existing asset from earlier work this session; the file content was replaced with this
  newer, user-supplied source since the user explicitly asked for these two new images to be
  used)
- **Final background dimensions:** 768×1328 px, RGB (1376 − 48 px status-bar crop)

Both assets registered in `flutter_app/pubspec.yaml` under `flutter: assets:` (the background
entry already existed; a new entry was added for `assets/brand/binnacle_logo.png`).

---

## 2. SPLASH SCREEN IMPLEMENTATION

- **Splash widget/file:** `flutter_app/lib/ui/screens/splash_screen.dart` — rewritten from a
  `StatelessWidget` showing only static text to a `StatefulWidget` (`SingleTickerProviderStateMixin`)
  that renders the transparent logo and "CONNECT" wordmark over `BinnacleBackground`
  (`assets/backgrounds/wave_glow.png`), with a staggered fade/scale entrance animation:
  - Logo: `FadeTransition` + `ScaleTransition` (0.88× → 1.0×, `Curves.easeOutCubic`) over the
    first 65% of a 1400 ms `AnimationController`.
  - "CONNECT" wordmark: fades in over the animation's final 55%, so it visibly follows the mark
    landing rather than animating in unison with it.
- **Minimum splash duration:** Implemented in `flutter_app/lib/main.dart`'s `_AppStartup` as a
  `static const _minimumSplashDuration = Duration(milliseconds: 3500)`, i.e. a genuine 3.5-second
  floor.
- **App-readiness / startup behavior:** `_AppStartup.initState()` now does
  `Future.wait([restoreFuture, minimumFloor]).then(...)` — it genuinely **awaits**
  `PairingService.restore()` (a real Keychain/Keystore read via `flutter_secure_storage`)
  together with the 3.5 s floor, and only swaps to `_RootShell` once **both** have settled. This
  replaces the prior implementation, which fired `restore()` without awaiting it alongside an
  unrelated fixed 450 ms `Timer` — i.e. the splash previously had no real relationship to
  readiness at all.
  - A `restoreFuture.catchError((_) {})` was added so that a failed credential read (corrupt
    storage entry, platform channel unavailable, etc.) cannot brick launch behind a permanent
    splash — failing to restore just means the app starts unpaired, which
    `PairingService.isPaired`/`role` already treat as the fail-closed default. This was found to
    be a real, previously-latent gap (see §4, Defects found).
- **Transition target:** `_RootShell` (the existing bottom-nav shell — My Boat / Live / Session /
  Library / Community). No changes made to auth, navigation, deep-link, or Core-init logic; the
  splash gate only delays when `_RootShell` is first built, using the same `PairingService`
  instance and provider tree already wired in `main.dart`.
- **Responsive layout approach:** `BinnacleBackground`'s existing `Stack(fit: StackFit.expand)` +
  `Image.asset(..., fit: BoxFit.cover)` means the background always fills the viewport regardless
  of aspect ratio; the logo/wordmark column is centered via `Scaffold.body: Center(...)` with
  `MainAxisSize.min`, so it does not depend on a fixed screen size.

---

## 3. PHYSICAL DEVICE VALIDATION

**Not performed in this session.** This environment has no `adb` binary and no physical Android
device attached (`adb: command not found`) — unlike a prior, separate session recorded in
`docs/evidence/S25_ULTRA_DEVICE_ACCEPTANCE.md`, which used a real Samsung Galaxy S25 Ultra over
`adb` for a different feature set. That prior device-acceptance record does **not** cover this
splash/branding feature and should not be read as validating it.

As a **substitute, non-physical-device** check, the demo-mode web build (`flutter build web`)
was served locally and rendered in this session's browser pane:
- At default desktop viewport: logo, transparent background compositing, and "CONNECT" wordmark
  all rendered correctly with the fade/scale entrance visibly playing.
- Re-rendered at an emulated 375×812 mobile viewport (a phone aspect ratio, though not an exact
  S25 Ultra resolution/DPI match): background still filled edge-to-edge via `BoxFit.cover`, and
  the logo/wordmark stayed centered and fully legible with no overflow or clipping.

No screenshot file could be saved to disk from this browser-pane preview in this session — the
tooling available here returns preview images for inline viewing only, with no mechanism to
persist them as a file the way the prior session's `adb screencap` evidence (e.g.
`docs/evidence/connect_first_launch.png`) was produced. This is stated plainly rather than
fabricating a screenshot artifact; see the accompanying final report's screenshot-evidence line
for the same disclosure.

**Limitation, stated honestly:** the "S25 Ultra verification" and "screenshot evidence" items are
therefore **not satisfied by a physical-device or saved-image artifact** for this specific
feature. The responsive-layout claim above is based on emulated-viewport browser rendering only.

---

## 4. AUTOMATED VERIFICATION RESULTS

- **`dart analyze`:** Pass — 0 errors, 0 warnings. 54 pre-existing `info`-level style lints
  remain (all in files untouched by this task, e.g. `prefer_const_constructors` suggestions);
  none introduced by this change.
- **`flutter test` (default/demo mode):** Pass — 47/47 tests. Required updating the pump duration
  after `pumpWidget(const BinnacleConnectApp())` in `test/widget_test.dart` (7 call sites) and
  `test/live_mode_test.dart` (2 call sites) from 500 ms to 3600 ms, since the new 3.5 s splash
  floor otherwise leaves the splash still showing when those tests try to interact with
  `_RootShell` content.
- **Core-mode `flutter test test/live_mode_test.dart --dart-define=BINNACLE_APP_MODE=core
  --dart-define=BINNACLE_CORE_URL=https://core.invalid`:** Pass — 1/1, after a second, real fix
  (see Defects found below).
- **`tools/connect_audit/connect_audit.py flutter_app/lib`** (run with
  `PYTHONUTF8=1 PYTHONIOENCODING=utf-8`): Pass — "No findings" /
  `STATIC_AUDIT_PASSED_UNEXECUTED`.
- **`flutter build web` (demo mode, `--dart-define=BINNACLE_APP_MODE=demo`):** Pass — built to
  `build/web`.
- **`flutter build web` (core mode, `--dart-define=BINNACLE_APP_MODE=core
  --dart-define=BINNACLE_CORE_URL=https://core.invalid`):** Pass — built to `build/web`.
- **`flutter build apk --debug`:** Pass — built
  `build/app/outputs/flutter-apk/app-debug.apk`. (Debug build only; no release/signing performed,
  no install onto a device — see §3.)

### Defects found and fixed during this task

1. **Genuinely-awaited `PairingService.restore()` exposed a latent bug in the Core-mode test.**
   Making `_AppStartup` actually wait on `restore()` (instead of firing it without awaiting, as
   before) meant `test/live_mode_test.dart` — which, unlike `widget_test.dart`, never called
   `FlutterSecureStorage.setMockInitialValues({})` — left the platform channel call unresolved
   under `flutter_test`'s fake-async `pump()`, so the splash never cleared and the test failed
   with `StateError: Bad state: No element`. Root-caused via a minimal reproduction harness
   outside the full app before touching the real test. **Fix:** added the same
   `FlutterSecureStorage.setMockInitialValues({})` stub `widget_test.dart` already uses, at the
   top of the failing test, with a comment explaining why it's newly required.
   Confirmed both re-run stages (Core-mode test, then the full default suite) pass after the fix.
2. **`PairingService.restore()` had no error handling**, which the old fire-and-forget call
   masked. Once awaited for real, an unrecoverable credential-store failure would have hung
   `_AppStartup` on the splash screen forever. **Fix:** `restoreFuture.catchError((_) {})` in
   `_AppStartup`, so restore failure degrades to "start unpaired" instead of blocking launch — see
   §2 for the reasoning.

### Remaining limitations

- Physical S25 Ultra (or any physical device) install/launch verification was not performed —
  see §3.
- No screenshot file evidence could be saved from the browser-pane preview in this session — see
  §3.
- The wave-background watermark removal was a manual local-blur compositing step rather than a
  general-purpose background-removal algorithm; it is visually clean in this specific image but
  is not a reusable technique for arbitrary future source images.
