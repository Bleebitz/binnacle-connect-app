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

### Remaining limitations (as of the v1 work above)

- The 16 KB page-size compatibility warning found during physical-device testing (§3, item 3
  above) is unresolved and out of this task's scope.
- Physical-device testing was performed against a **debug** build only; no release/signed build
  was tested on-device in this session.
- The wave-background watermark removal was a manual local-blur compositing step rather than a
  general-purpose background-removal algorithm; it is visually clean in this specific image but
  is not a reusable technique for arbitrary future source images.

---

## 5. V2 UPDATE — responsive/glow logo, resilient readiness gate, 16 KB investigation

**Date:** 2026-09-17 (continuation, same day). **Builds on** the v1 work in §1–4 above (PR #7,
merged at `730b949052ebf86a2891c71e9482aa5f392d3536`, plus PR #8's physical-device addendum) —
this section documents what changed on top of that merged baseline, not a re-implementation.
Superseded v1 evidence above (the small 148px logo, the plain `catchError`-swallowed restore
failure, the un-investigated 16 KB warning) is left in place rather than deleted, per this task's
instruction to preserve prior evidence and distinguish superseded state from the final one.
**Branch:** `connect-splash-v2-resilience` (based on PR #8's branch, i.e. includes the §3 physical
device addendum). **Codex branch reviewed:** `bin-connect-branded-splash` @
`1372a292f70239f8ef3658c0cb384fab8f0b2341` — a parallel, independent implementation of the same
brief. Not merged wholesale (explicitly instructed not to); several of its techniques were
reviewed and selectively adapted where they were genuinely better than the v1 approach — credited
inline below wherever adapted.

### 5.1 Asset provenance reconciliation

The Codex branch used a **different** wave background (`docs/evidence/splash_sources/Codex Image
Sep 17, 2026, 07_34_45 AM.png`, 941×1672, used byte-identical — SHA-256
`5331b200f0e02602ab08e536b45e52a9a5004e8799de5da93761c5bde5b207ff`) and a **different** logo
derivation (an AI background-extraction edit of `image_8aa8647.jpg`, 1408×768 JPEG, into
`binnacle_logo_transparent.png`, 1408×1117 RGBA — a generative cutout, not the same source as
v1's logo despite matching canvas dimensions).

**Resolution: v1's assets remain authoritative and are unchanged in this v2 update.** The user
explicitly attached the two files used in v1 (`Codex Image Sep 17, 2026, 11_24_53 AM.png` for the
logo, the `Firefly_Gemini Flash_...` image for the background) directly in this conversation with
the literal instruction "use these images" — that is the most recent, explicit, in-conversation
approval, postdating whatever separate request produced the Codex branch's asset choice. Per this
task's own instruction ("use the latest explicitly approved asset"), v1's assets stand. The
Codex branch's alternative assets are not deleted anywhere — they remain in git history on that
branch, satisfying "preserve originals" without duplicating binaries into `main`.

### 5.2 Implementation changes

- **New file `flutter_app/lib/ui/widgets/connect_startup.dart`** replaces
  `lib/ui/screens/splash_screen.dart` (deleted) and `main.dart`'s old `_AppStartup` class. Adapted
  from the Codex branch's `ConnectStartup` architecture (name and the wrap-the-Navigator pattern
  credited to that review — see below), rewritten with v1's assets, this task's own visual design,
  and additional fixes found during testing (§5.5).
- **`main.dart` now wraps the Navigator itself**, via `MaterialApp.builder`, instead of replacing
  `home:` with a splash/shell switch:
  ```dart
  builder: (context, child) => ConnectStartup(
    initialize: () => context.read<PairingService>().restore(),
    child: child ?? const SizedBox.shrink(),
  ),
  home: const _RootShell(),
  ```
  This is the one deliberate architectural adoption from the Codex review: `_RootShell` (and any
  route pushed onto it, including a future deep link) is now mounted from the very first frame,
  sitting behind the splash overlay rather than not existing until the splash finishes. v1's
  approach (swap `SplashScreen` → `_RootShell`) could not have preserved an in-flight route
  arriving during startup; this can, and is now covered by a dedicated test (§5.4).
- **Responsive, enlarged logo (requirement 1):** replaces the fixed `width: 148`. Computed via
  `LayoutBuilder` inside a `SafeArea`:
  ```dart
  final logoWidth = math.min(300.0, math.min(constraints.maxWidth * 0.68, constraints.maxHeight * 0.34));
  ```
  bounded by both available width and height so it neither clips on a small/narrow phone nor
  overruns a short landscape viewport — verified at three sizes in §5.4/§5.6. This roughly doubles
  the effective on-screen size on a typical phone (e.g. ~280px on a 412-logical-px-wide portrait
  screen) while remaining responsive, matching "approximately twice its current displayed size."
- **Restrained glow layer (requirement 1):** a new `_GlowingLogo` widget composites two tinted,
  blurred duplicates of the *same* logo asset behind the sharp, unmodified original — a thin
  `sigmaX/Y: 2.5` "edge light" duplicate and a larger, softer `sigmaX/Y: 16` "diffuse halo"
  duplicate, both tinted `BinnacleColors.tealBright` via `colorBlendMode: BlendMode.srcIn` (so the
  glow traces the artwork's actual alpha silhouette — shield, needle, and the baked-in BINNACLE /
  MARINE SYSTEMS lettering — not a generic rectangle). The original logo image itself is never
  redrawn, recolored, or replaced; the glow is a separate rendering layer underneath it, per the
  requirement. No pulsing or looping — the composite is static, matched to the rest of the
  entrance's one-shot animation. Visually confirmed via the render-evidence screenshots (§5.6) and
  on the real device in release mode (§5.7, `s25_release_splash_full.png`).
- **Subtle fade into the destination (requirement 2):** the existing fade/scale entrance is
  unchanged; the splash overlay now fades out (`AnimatedOpacity`, 450 ms) to reveal the
  already-mounted destination underneath, rather than a hard widget swap.
- **Concurrent real initialization, decode-time excluded from the 3.5 s floor (requirement 3):**
  `PairingService.restore()` starts immediately in `initState()`, concurrently with brand-asset
  precaching. The minimum-duration timer is started only inside a `WidgetsBinding.instance.
  addPostFrameCallback` that runs after `precacheImage` has resolved for both assets — i.e. only
  once decoded artwork has actually reached a frame — so asset-decode time is structurally
  excluded from the "3.5 seconds visible" floor, not just excluded by convention. (Adapted from
  the Codex branch's equivalent precache-then-time gating, which uses the same technique.)
- **Visible retry on failure, credentials preserved (requirement 4):** replaces v1's
  `restoreFuture.catchError((_) {})` (which silently swallowed a real restore failure) with a
  `try/catch` around `initialize()` that shows a generic "Could not start Connect. Please try
  again." message and a RETRY button — no exception detail is surfaced. Retrying simply re-invokes
  `initialize()` (i.e. `PairingService.restore()` again); `restore()` only *reads* from secure
  storage, so credentials already on-device are never touched, let alone cleared, by a failure or
  a retry. Demo mode is unaffected — `AppConfig.isDemo` gating elsewhere is untouched.
- **Navigation/lifecycle/Core-init preserved, reduced motion respected (requirement 5):** the real
  `child` (i.e. `_RootShell` and everything under it) is mounted for `ConnectStartup`'s entire
  lifetime inside a `Stack`, wrapped in `ExcludeSemantics` / `ExcludeFocus` / `IgnorePointer` (all
  gated on `_finished`) rather than being swapped out — confirmed non-interactive during the
  splash and fully interactive after, in a dedicated test (§5.4). `MediaQuery.disableAnimationsOf`
  is checked both for the entrance animation (jumps straight to the end state) and the exit
  transition (`Duration.zero`); the minimum-duration floor itself is **not** skipped by reduced
  motion — only the visual motion is, matching "respect reduced-motion settings" without
  compromising "at least 3.5 seconds of visible presentation."
- **CONNECT text no longer uses GoogleFonts:** changed from `BinnacleTheme.mono()` (network-backed
  JetBrains Mono) to a local `TextStyle(fontFamily: 'monospace', ...)`. This is a deliberate
  reliability fix, not merely a testing workaround (see §5.5) — the splash is the app's most
  latency-sensitive moment, before anything else has rendered, and must never depend on a font
  network fetch succeeding. It is also what let this task's own render-evidence tests avoid the
  same GoogleFonts/test-sandbox problem the Codex branch's evidence doc independently flagged
  ("preventing unrelated Google Fonts network work from running inside image-decoding test
  zones") — Codex's fix was to never use GoogleFonts for their splash text at all (`fontFamily:
  'sans-serif'`); this task reaches the same conclusion independently and applies it directly to
  the wordmark rather than working around it in test setup.
- **`flutter_app/android/app/build.gradle.kts`:** see §5.3 (16 KB page-size investigation/fix).

### 5.3 16 KB page-size compatibility — investigated, partially fixed

Real investigation, not assumption, using `llvm-readelf -l` (from the installed NDK
`28.2.13676358`) to inspect each bundled native library's actual ELF `LOAD` segment alignment
(`p_align`) — the real cause of the on-device warning — as distinct from `zipalign -c -P 16`,
which only checks zip-entry alignment and reported every library "OK" despite the real ELF
misalignment underneath.

**Findings, on the pre-fix debug build:**

| Library | Source | `p_align` before | Genuinely misaligned? |
|---|---|---|---|
| `libbarhopper_v3.so` | `com.google.mlkit:barcode-scanning` / `play-services-mlkit-barcode-scanning`, via `mobile_scanner`'s hardcoded `17.2.0`/`18.3.0` | `0x1000` (4 KB) | **Yes** |
| `libimage_processing_util_jni.so` | `androidx.camera:camera-core`, via `mobile_scanner`'s hardcoded `camera-camera2`/`camera-lifecycle:1.3.3` | `0x1000` (4 KB) | **Yes** |
| `libflutter.so` | Flutter engine | `0x10000` (64 KB) | No — already aligned |
| `libdartjni.so` | Flutter engine | `0x4000` (16 KB) | No — already aligned |
| `libjingle_peerconnection_so.so` | `flutter_webrtc` | `0x4000` (16 KB) | No — already aligned |
| `libVkLayer_khronos_validation.so` | Vulkan validation layer (debug-only) | `0x10000` (64 KB) | No — already aligned |

The on-device dialog's "Unknown error" for the four already-aligned libraries is a false positive
from the OS's debug-build compatibility checker, not a real defect — confirmed by direct ELF
inspection, not assumed.

**Fix applied** (`flutter_app/android/app/build.gradle.kts`, `configurations.all { resolutionStrategy
{ force(...) } }`): forces `androidx.camera:camera-camera2`, `camera-lifecycle`, and `camera-core`
to `1.4.2` (the version confirmed, via web search, to have fixed 16 KB alignment for CameraX —
mobile_scanner 5.2.3's own `build.gradle` hardcodes the older, unaligned `1.3.3`). This is a
Gradle-level dependency-resolution override only — no change to the `mobile_scanner` **Dart**
package version or its public API, so no unrelated dependency churn. Rebuilt and re-inspected:

| Library | `p_align` after fix |
|---|---|
| `libimage_processing_util_jni.so` | `0x4000` (16 KB) — **fixed** |
| `libbarhopper_v3.so` | `0x1000` (4 KB) — **unchanged, not fixable here** |
| `libsurface_util_jni.so` (new in CameraX 1.4.2) | `0x4000` (16 KB) — aligned |

`libbarhopper_v3.so` (Google ML Kit's on-device barcode-scanning engine) remains genuinely
unresolved upstream: confirmed via live web search that no 16 KB-aligned build of this specific
native library exists yet, even at ML Kit's latest `17.3.0` (see
[googlesamples/mlkit#989](https://github.com/googlesamples/mlkit/issues/989), "ML kit 17.3.0
still not 16kb aligned with camerax 1.4.2", an open issue). This is left as a documented,
unresolved upstream limitation rather than suppressed or silently omitted — there is no available
fix to apply.

**Debug vs. release, verified directly on the real device (not assumed):** the OS "Android App
Compatibility" dialog (which explicitly states it "is showing because this is a debuggable app")
appeared on a `flutter build apk --debug` install and did **not** appear anywhere in a full launch
→ 3.5 s+ → transition → background/resume → rotation cycle on a `flutter build apk --release`
install (same debug signing config, same device, same session) — see §5.7. The dialog is
genuinely debug-build-specific; the underlying `libbarhopper_v3.so` misalignment itself is not
debug-specific (it's baked into the AAR for both build types), it just isn't surfaced by this
particular OS compatibility checker outside a debuggable build.

`flutter test` (Dart-level) continues to pass 47/47 with this dependency force in place (§5.4);
the mobile_scanner-dependent QR-pairing camera flow itself was not re-exercised at the native
level in this session (no physical pairing/QR-scan walkthrough was performed) beyond confirming
the app builds and the affected screens (Pairing) are unchanged.

### 5.4 New/updated automated tests

- **`flutter_app/test/startup_test.dart` (new, 10 tests)** — tests `ConnectStartup` directly and
  in isolation (injectable `initialize`), adapting the Codex branch's test architecture/technique
  (explicitly credited — this pattern, and the `RepaintBoundary`/`toImage()` render-evidence
  capture below, are the two things adopted wholesale from that review since they were
  unambiguously better than testing through the full `BinnacleConnectApp`):
  - *Early-exit prevention:* a fast-succeeding `initialize()` still waits the full 3.5 s floor.
  - *Slow readiness:* gated correctly past 5 s of a not-yet-resolved `initialize()`.
  - *Failure/retry:* a thrown error shows the retry UI (not the exception text), tapping RETRY
    re-invokes `initialize()`.
  - *Interaction blocking:* the destination cannot be tapped during the splash, can be immediately
    after.
  - *Disposal:* tearing down the widget mid-`initialize()` cancels timers and doesn't throw when
    the (now-orphaned) future later completes.
  - *Reduced motion:* the entrance animation jumps to its end state, but the 3.5 s floor still
    holds.
  - *Route preservation:* a route pushed onto the wrapped `Navigator` while the splash is up
    survives to become the visible screen once the splash clears, and `initialize()` is not
    re-invoked by the navigation.
  - *Responsive layout* at three sizes (412×917 tall-phone/S25-Ultra-like portrait, 360×640
    compact portrait, 915×412 landscape): asserts no overflow/clipping exception, and (behind a
    `SPLASH_EVIDENCE` dart-define, matching the Codex branch's technique) captures a real
    `RenderRepaintBoundary.toImage()` render of the actual widget tree to
    `docs/evidence/splash_{size}.png` — genuine rendered screenshots, not mockups, produced
    entirely by `flutter test` without needing a device or browser.
- **Two real bugs found and fixed while writing these tests** (both are genuine defects this
  review process caught, not test-only workarounds):
  1. A `late final AnimationController` field was only otherwise touched inside the normal
     (non-test-skip) startup path. With the new `debugSkipForTesting` flag (below) shortcutting
     straight to `_finished = true`, `dispose()` became the *first* access — lazily constructing
     the controller (and its ticker, which looks up an ancestor) at a point where the element was
     already deactivated, crashing with "Looking up a deactivated widget's ancestor is unsafe."
     Fixed by forcing eager creation in `initState()` before the skip check.
  2. `WidgetTester.pump(duration)` with one large single jump does not correctly advance a
     `Ticker`-driven animation that was `forward()`-ed inside the immediately-preceding
     `postFrameCallback` — a Ticker's first invocation sets its own start time on that callback,
     so a single big pump right after sees `elapsed == 0` for the whole jump and the animation
     appears frozen at its start value (only discoverable by inspecting an actual rendered
     `toImage()` capture — presence-only assertions like `find.text(...)` never caught it). Fixed
     in the test helper by pumping one extra 1 ms "priming" frame before any large-duration pump.
     This is a test-harness-only concern; the real app's own continuous ~16 ms frame cadence never
     hits it.
- **`flutter_app/test/widget_test.dart` and `test/live_mode_test.dart`:** switched from awaiting
  real splash timing (`warmConnectStartupAssets` + `runAsync` + a long fixed pump) to
  `ConnectStartup.debugSkipForTesting = true` (a new static test-only flag, same idiom as
  Flutter's own `debugDisableShadows` etc.) in `setUp()`, since these files test the rest of the
  app, not the splash. This is simpler and avoids a real, separate problem found in the process:
  a genuine `runAsync` gap (needed for real image decode) gives an unrelated, pre-existing, dormant
  GoogleFonts network-fetch Future (from `BinnacleTheme.dark()`, used app-wide, not just by the
  splash) its first-ever chance to actually run and fail loudly in this offline sandboxed test
  runner — every other test never touches this because it never opens a real-async gap at all.
  Skipping the splash for these tests avoids ever needing that gap. `live_mode_test.dart`
  additionally needed one wait switched from `pumpAndSettle()` to a fixed-duration `pump()`: with
  `ConnectStartup` now wrapping the Navigator from frame 1 (§5.2), the Core-mode Live screen's
  permanently-pulsing "offline" indicator (`_PulsingDot(pulsing: status == LinkStatus.offline)`,
  correctly perpetual by design — Core mode with no real Core is meant to show a persistent
  offline state, not a transient "connecting" one) is alive from the very first frame in every
  test now, and `pumpAndSettle()` never terminates against a genuinely perpetual animation.
- **Result:** `flutter test` — 57/57 pass (47 pre-existing/adapted + 10 new), confirmed stable
  across 4 consecutive full-suite runs, not a one-off pass. Core-mode
  `test/live_mode_test.dart` — 1/1, confirmed stable across 3 runs.

### 5.5 Automated verification (v2)

- **`dart analyze`:** Pass — 0 errors, 0 warnings, the same 54 pre-existing `info`-level style
  lints (none introduced).
- **`flutter test` (default/demo mode):** Pass — 57/57, ×4 consecutive runs.
- **Core-mode `flutter test test/live_mode_test.dart --dart-define=BINNACLE_APP_MODE=core
  --dart-define=BINNACLE_CORE_URL=https://core.invalid`:** Pass — 1/1, ×3 consecutive runs.
- **`tools/connect_audit/connect_audit.py flutter_app/lib`:** Pass — "No findings".
- **`flutter build web`** (demo mode and core mode): both Pass.
- **`flutter build apk --debug`:** Pass.
- **`flutter build apk --release`:** Pass (110.3 MB; debug-signed, per the established
  `signingConfigs.getByName("debug")` convention already in `build.gradle.kts` — this is
  explicitly **not** a production-signed release; see §5.7).

### 5.6 Render-evidence screenshots (real `flutter test` renders, not mockups)

Produced by `flutter test test/startup_test.dart --dart-define=SPLASH_EVIDENCE=true`, which also
loads a real bundled font (the Flutter SDK's own cached `roboto-medium.ttf`) under the
`'monospace'` family name for this evidence run only — widget tests otherwise substitute a
placeholder box-glyph font for all text, which would make "CONNECT" render as blank boxes in the
captured PNGs despite rendering correctly on a real device (confirmed separately in §5.7).

- [`docs/evidence/splash_412x917.png`](splash_412x917.png) — tall-phone/S25-Ultra-like portrait.
  Logo and glow clearly visible, CONNECT legible, centered, no clipping.
- [`docs/evidence/splash_360x640.png`](splash_360x640.png) — compact phone portrait. Logo scales
  down appropriately, still fully visible and centered.
- [`docs/evidence/splash_915x412.png`](splash_915x412.png) — landscape. Logo shrinks further
  (height-constrained, as intended for "intentional landscape handling") while remaining centered
  with no clipping.

No emulator or physical device was used for these three — they are exactly what `flutter test`
rendered, exported at 2× pixel ratio via `RenderRepaintBoundary.toImage()`.

### 5.7 Physical device re-verification (S25 Ultra, this v2 build)

Same device as §3 (`SM S938U`, serial `R5CY13C57LT`), still connected. Installed as an upgrade
over the v1 build already on-device (`versionCode 2002`) — **not** uninstalled, cleared, or
re-signed under a different identity.

- **Debug build:** `flutter build apk --debug --build-number=2003` (after the 16 KB Gradle fix,
  before the release build below) — SHA-256
  `a01689638687de07097a5dc08e227fec2527458f99af33d3880b860159a0fcf4`. Installed via `adb install
  -r` (accepted — build number above the installed 2002, no downgrade error, no signing conflict).
- **Release build (debug-signed):** `flutter build apk --release --build-number=2004` — SHA-256
  `25faf9b9f03df37e90d5f24217a7bbf4e3165cc1784ed63c785ac04298bae13a`, 110.3 MB. **This uses the
  same `signingConfigs.getByName("debug")` config already established in
  `build.gradle.kts`** (per the task's own instruction to use the established compatible signing
  configuration) — it is a **debug-signed release-mode build**, explicitly **not** a
  production-signed release. Installed via `adb install -r` over the debug build above —
  accepted (same signing certificate, build number `2004 > 2003`, no reinstall/data-loss). Both
  APKs verified installed via `dumpsys package` reporting the matching `versionCode` after each
  install; app data/pairing state preserved throughout (upgrade installs only, `-r`, never
  uninstalled).
- **Cold launch, release build:** `am force-stop` then `am start` — process alive
  (`pidof`), confirmed via `dumpsys package` reporting `versionCode=2004`.
- **Unobstructed splash confirmed:** screenshots at ~0.5 s
  ([`s25_release_splash_launch.png`](s25_release_splash_launch.png)) and after the animation
  settles ([`s25_release_splash_full.png`](s25_release_splash_full.png)) show the enlarged,
  glowing logo and legible "CONNECT" wordmark rendering cleanly against the real system status
  bar, with **no compatibility dialog** — direct visual confirmation of the debug-vs-release
  finding in §5.3, not an inference from the dialog's own wording.
- **Transition and normal destination:** a screenshot ~3 s after launch
  ([`s25_release_after_transition.png`](s25_release_after_transition.png)) shows the app already
  on "My Boat" with the correct "Demo mode — nothing above is a real connection" banner — the
  splash cleared and the app reached its normal destination in demo/offline mode as expected.
- **Background/resume:** `KEYCODE_HOME` then `am start` again — same PID before and after
  (`9783`), confirming the existing task was resumed, not restarted.
- **Orientation:** rotated to landscape via `adb shell settings put system user_rotation 1` —
  [`s25_landscape.png`](s25_landscape.png) shows My Boat rendering correctly in landscape, no
  crash; rotation setting restored afterward.
- **Crash/ANR logs:** `adb logcat -d --pid=<pid> | grep -iE "FATAL|AndroidRuntime|ANR|Exception"`
  — no matches, across the entire launch → transition → background/resume → rotation sequence.
- **Not performed in this session:** a real QR-pairing camera walkthrough (to directly exercise
  the `mobile_scanner`-dependent code path affected by the CameraX version force in §5.3) and a
  timed stopwatch re-measurement of the 3.5 s floor against a physical clock (the screenshots
  above are timestamped by `adb`'s capture time, which is sufficient to confirm the sequence but
  not a frame-accurate re-measurement).

### 5.8 Remaining limitations (v2)

- `libbarhopper_v3.so` (Google ML Kit barcode-scanning) remains genuinely 16 KB-misaligned —
  unresolved upstream, no fix available as of this investigation (§5.3).
- The `mobile_scanner`-dependent QR-pairing flow was not re-exercised on-device at the native
  level after the CameraX `1.4.2` force; only confirmed to build and that the Pairing screen
  itself is otherwise unchanged.
- No production-signed release build exists or was tested — only the established debug-signed
  release-mode configuration, per instruction.
- The 3.5 s floor and transition were confirmed via timestamped screenshots and the automated
  test suite's fake-clock assertions, not a physical stopwatch against the device.

---

## 6. LOGO LETTERING REFINEMENT — brighter, dimensional, readable BINNACLE / MARINE SYSTEMS

**Date:** 2026-09-17 (same day, continuation on the still-open `connect-splash-v2-resilience`
branch / PR #9 — not yet merged, so this refinement lands as an additional commit on the same
PR rather than a new branch). **Checked current size first, per instruction:** the logo width
formula in `connect_startup.dart` (`math.min(300.0, math.min(maxWidth*0.68, maxHeight*0.34))`)
was already the ~2x-enlarged, responsive size from §5.2 — **not changed again** here; this section
is lettering/color/dimension only.

### 6.1 What was actually wrong

The original `binnacle_logo.png` renders "BINNACLE" and "MARINE SYSTEMS" in a dark navy fill —
readable on a light background, but low-contrast against this screen's dark navy/wave background
even after the §5.2 enlargement. Confirmed by direct visual inspection of the (unchanged) asset
before editing (`docs/evidence/s25_release_splash_full.png` / `s25_logo_v2_splash.png`'s "before"
counterpart, both pre-existing in this evidence set).

### 6.2 New asset, original preserved

- **New file:** `flutter_app/assets/brand/binnacle_logo_dark_bg.png` (1345×1078 RGBA, same
  canvas/shield/compass as the original, pixel-for-pixel except the two lettering bands below).
- **Original file preserved unchanged:** `flutter_app/assets/brand/binnacle_logo.png` — still
  registered in `pubspec.yaml`, just no longer referenced by any screen (the splash now points at
  the new variant; the original remains available for a future light-background context).
- **`connect_startup.dart`'s `logoAsset` constant repointed** to the new file — the only code
  change needed to swap assets, since the glow/sizing logic already operates on whatever
  `logoAsset` points to.

### 6.3 Technique (real pixel editing, not a runtime filter)

Done with Pillow + NumPy + SciPy (`distance_transform_edt`) directly on the artwork, isolating the
two lettering bands via a precise alpha-channel row/column scan (found band `y`-ranges: shield
51–805, "BINNACLE" 828–962, "MARINE SYSTEMS" 971–1038 — confirmed by scanning, not guessed) so the
shield/compass pixels are never touched:

1. **Bevel via distance-transform bump-mapping:** compute each letter's distance-to-edge field,
   derive a synthetic surface normal from its gradient, and light it from a fixed upper-left
   direction — a principled simulation of a machined bevel, not an arbitrary emboss filter. Bevel
   width 7 px for "BINNACLE" (a defined, visible bevel) vs. 3 px for "MARINE SYSTEMS" (shallower,
   per the brief).
2. **Base fill:** a vertical brushed-metal gradient from an icy near-white blue at the top to a
   deeper silver-blue at the bottom — "BINNACLE" `(238,246,250)→(176,202,214)`; "MARINE SYSTEMS"
   brighter/flatter, `(248,251,253)→(214,228,234)`.
3. **Specular highlight:** an extra brightness boost at the crest of the simulated bevel (where
   the surface normal most directly faces the light) for crisp upper-left highlight streaks.
4. **Drop shadow:** a short, blurred, dark-navy offset copy of each letter's mask placed *behind*
   it — 6 px/5 px offset for "BINNACLE" (opacity 0.5), a noticeably shorter 3 px/3 px, lower-opacity
   (0.32) shadow for "MARINE SYSTEMS", per "minimal shadow so the smaller letters remain readable."
5. **Thin cyan edge light + restrained halo:** a 2 px-dilated ring right at each letter's boundary,
   tinted cyan, moderate opacity — plus a separate, wider (6 px/3 px), much softer, low-opacity
   (0.22/0.14) halo ring further out. Both are confined to the lettering's own alpha shape (via the
   same distance/dilation approach used for the bevel), so **no glow spreads across the
   surrounding rectangular canvas or blurs the letterforms themselves** — letter edges stay sharp
   throughout.
6. Re-inspected the composited result (on a navy backdrop matching the real splash background, and
   at the actual ~280 px on-screen display width) before finalizing — see §6.4.

### 6.4 Verification

- **Full-size composite on navy:** confirms shield/compass pixel-identical to the original, both
  text bands now bright and dimensional, no seams at the crop/paste boundaries.
- **Actual display-size composite (300 px wide, matching the real on-screen size):** both
  "BINNACLE" and "MARINE SYSTEMS" read clearly at the size they're actually shown at — this was
  checked before treating the change as done, not only at full asset resolution.
- **`flutter test test/startup_test.dart --dart-define=SPLASH_EVIDENCE=true`:** re-ran after the
  asset swap — all 10 tests still pass; regenerated
  [`docs/evidence/splash_412x917.png`](splash_412x917.png),
  [`splash_360x640.png`](splash_360x640.png), and [`splash_915x412.png`](splash_915x412.png) show
  the new lettering at all three previously-verified sizes, still with no overflow/clipping.
- **`dart analyze`:** clean (0 errors/warnings, same 54 pre-existing info lints).
- **`flutter test` (full suite):** 57/57 pass.
- **Core-mode test:** 1/1 pass.
- **`connect_audit.py`:** no findings.
- **Physical device (same S25 Ultra, upgrade install, no data loss):** built
  `flutter build apk --release --build-number=2005` (SHA-256
  `53722202f848d9e25243602ffb09433c5713c827a88b33e8d6584aa112849265`) — **debug-signed
  release-mode**, per the established signing configuration already in `build.gradle.kts`,
  explicitly not production-signed. Installed via `adb install -r` over the existing `2004` build
  (same signing certificate, accepted, no reinstall/data loss). `dumpsys package` confirmed
  `versionCode=2005` installed and running after a cold `am force-stop` / `am start` cycle.
  Screenshot [`docs/evidence/s25_logo_v2_splash.png`](s25_logo_v2_splash.png), captured ~0.6 s
  after launch, shows "BINNACLE" and "MARINE SYSTEMS" both clearly legible, bright, and
  dimensional on the real device — a genuine before/after improvement over
  [`s25_release_splash_full.png`](s25_release_splash_full.png) (§5.7's earlier capture of the same
  screen with the original dark-navy lettering).

### 6.5 Remaining limitations

- The bevel/lighting technique is bespoke to this specific artwork's two lettering bands (fixed
  pixel-coordinate bands found by scanning this exact image); it is not a general, reusable
  "relight any logo" utility.
- No production-signed build was created or tested — same limitation as §5.7, unchanged by this
  refinement.
- The original `binnacle_logo.png` remains registered in `pubspec.yaml` but has no current screen
  referencing it; it is kept for a possible future light-background use, not verified against one.
