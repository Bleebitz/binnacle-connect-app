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

**Performed after the PR above was merged**, once the user's Samsung Galaxy S25 Ultra was
connected via USB in this session (initially reported as not performable — no `adb` binary was on
`PATH` — resolved once the SDK's `platform-tools` was located and added to `PATH`; a physical
device was then genuinely available, unlike the rest of this task).

- **Device:** `SM S938U` (Samsung Galaxy S25 Ultra), serial `R5CY13C57LT`, confirmed via
  `flutter devices` and `adb devices -l`. Already had a prior debug/release-signed build installed
  from the separate BIN-36 device-acceptance work (`versionCode 2001`).
- **Build installed:** `flutter build apk --debug` from `main` at commit
  `730b949052ebf86a2891c71e9482aa5f392d3536` (the merged commit containing this feature).
  `adb install -r` initially failed with `INSTALL_FAILED_VERSION_DOWNGRADE` (this debug build
  defaults to `versionCode 1`, below the device's existing `2001`); rebuilt with
  `flutter build apk --debug --build-number=2002` and installed successfully as an **upgrade**
  (`-r`, app data preserved — not a fresh install).
- **Launch:** `adb shell am start -n com.binnacleconnect.binnacle_connect/.MainActivity` —
  process started and stayed alive (confirmed via `pidof`); `dumpsys package` confirmed
  `versionCode=2002` installed and running.
- **Splash render, confirmed via real `adb shell screencap` pulled to
  `docs/evidence/s25_splash_launch.png`:** the transparent Binnacle logo and wave background
  render correctly on real hardware, composited cleanly against the actual system status bar (no
  double status-bar artifact, confirming the earlier source-image status-bar crop was correct).
- **Real defect found on-device (not seen in any emulated/browser check):** an OS-level "Android
  App Compatibility" dialog ("This warning is showing because this is a debuggable app which is
  currently being tested... This app isn't 16 KB compatible. ELF alignment check failed...")
  appears over the splash almost immediately on this Android 16 (API 36) device, listing several
  Flutter-engine and plugin native libraries (`libflutter.so`,
  `libjingle_peerconnection_so.so`, `libbarhopper_v3.so`, etc.) as not 16 KB page-size aligned.
  This is a **debug-build-only OS warning** (the dialog states it is shown "because this is a
  debuggable app"), not a crash — confirmed by dismissing it (tapped "OK" via
  `adb shell input tap`) and observing the app continue normally into its last-active tab
  (Session), process still alive, no ANR. It is a real forward-compatibility gap worth tracking
  separately (Android 15+/16 devices increasingly enforce 16 KB page alignment; a **release**
  build was not tested here and may or may not trigger the same dialog — that distinction was not
  verified in this session).
- **Screenshot evidence (real, saved to disk this time via `adb pull`, unlike the browser-only
  check below):**
  - `docs/evidence/s25_splash_launch.png` — splash logo/background visible on-device, partially
    covered by the compatibility dialog described above.
  - `docs/evidence/s25_after_dialog_dismiss.png` — app continuing normally (Session tab) after
    dismissing the dialog, confirming no crash.
- **Minimum-duration / animation timing:** not independently re-timed with a stopwatch against
  the device; the compatibility dialog appeared too quickly after launch to cleanly observe the
  fade/scale entrance in isolation on this device. The 3.5 s floor and animation logic themselves
  are unchanged from what `flutter test`'s fake-async pump already exercises (§4) — this is a
  rendering/visual confirmation, not a re-verification of the timing logic.

As an earlier, additional (non-physical-device) check performed before the device was available,
the demo-mode web build was also served locally and rendered in this session's browser pane at
both desktop and an emulated 375×812 mobile viewport, with the same visual result (no screenshot
file could be saved from that browser-pane preview — only the later `adb`-based captures above
are real saved image files).

**Limitation, stated honestly:** the 16 KB page-size compatibility warning above is a real,
unresolved finding from this physical-device check. It was not introduced by this task's changes
(it stems from Flutter-engine/plugin native libraries generally, not from anything in
`splash_screen.dart`, `main.dart`, or the new assets) and reproducing/fixing it is out of this
task's scope, but it should not be silently omitted from the record.

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
  `build/app/outputs/flutter-apk/app-debug.apk`, and (later, once a physical device was
  connected) `flutter build apk --debug --build-number=2002`, installed and launched on a real
  Samsung Galaxy S25 Ultra — see §3. Debug build only; no release/signing performed.

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
3. **(Physical-device finding, not fixed — out of scope) 16 KB page-size compatibility warning**
   on Android 16 (API 36) for this **debug** build, covering the splash on launch — see §3 for
   full detail. Not introduced by this task's changes; not reproduced or investigated against a
   release build.

### Remaining limitations

- The 16 KB page-size compatibility warning found during physical-device testing (§3, item 3
  above) is unresolved and out of this task's scope.
- Physical-device testing was performed against a **debug** build only; no release/signed build
  was tested on-device in this session.
- The wave-background watermark removal was a manual local-blur compositing step rather than a
  general-purpose background-removal algorithm; it is visually clean in this specific image but
  is not a reusable technique for arbitrary future source images.
