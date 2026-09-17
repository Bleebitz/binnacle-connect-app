# Connect branded startup and asset acceptance

Implementation date: 2026-09-17. Scope: Connect phone/cloud/operator app only.
Linear: [BIN-49](https://linear.app/binnacle-marine-systems/issue/BIN-49/connect-add-branded-binnacle-startup-splash-experience), child of BIN-32.
Repository: https://github.com/Bleebitz/binnacle-connect-app

## Discovery and history preservation

- Initial local branch: `bin-32/live-core-boundaries`, HEAD `3e83ea3`; clean working tree. Preserved unchanged.
- Verified canonical default: `main`; starting SHA `b7742dbeb4c3376933432ff1652254235813ba65`.
- Fetched all remote branches and reviewed recent commits, open and merged PRs, BIN-32 and its comments, Linear splash/startup/branding/logo searches, and the Master Register Evidence Index, Change Log and Linear Map before editing.
- Claude's secure pairing, WebRTC/media and prior S25 acceptance work was present on current main, including merged PRs #1, #2 and #3. These implementations and their evidence were retained.
- Existing draft PRs #4 (`bin-6-9-acceptance-audit`), #5 (`bin-38-connect-live-broadcast`), #6 (`bin-9-safety-mob-link-state`) are unrelated and untouched.
- Splash assets, transparency, widget, startup timing/readiness wrapper, splash tests/evidence/issue/register entry: **NOT PRESENT** at baseline. No partial splash implementation to reuse. Existing app architecture: reused.
- Delivery branch: `bin-connect-branded-splash`, based on canonical main above. Final implementation SHA and delivery/CI links are recorded in the delivery addendum below; the containing evidence commit is identified by Git history, avoiding an impossible self-referential commit hash.

## ASSET PREPARATION

| Role | Path | Dimensions |
|---|---|---|
| Original logo (preserved) | `docs/evidence/splash_sources/image_8aa8647.jpg` | 1408 × 768 |
| Original wave (preserved) | `docs/evidence/splash_sources/Codex Image Sep 17, 2026, 07_34_45 AM.png` | 941 × 1672 |
| Production wave | `flutter_app/assets/branding/connect_splash_background.png` | 941 × 1672 RGB |
| Production logo | `flutter_app/assets/branding/binnacle_logo_transparent.png` | 1408 × 1117 RGBA |

Original Downloads files were not modified. The production wave is a byte-identical copy, not cropped or regenerated.

SHA-256:
- Source logo: `fbb7ab1a1d7cfbb07572d1dbef38aae2ce3cc6dcfa9da24f8f4eabbbf7f11ee1`.
- Source and production wave: `5331b200f0e02602ab08e536b45e52a9a5004e8799de5da93761c5bde5b207ff`.
- Production logo: `2b5c33ec196b49f9e840ebf819236c509371c46b06d6e2ddf6f5238251723f1e`.

Logo method: built-in imagegen background-extraction edit using the supplied JPEG as the only input. Genuine alpha transparency was requested; no global white-pixel keying or manual pixel manipulation was used. The light compass face remains opaque/near-opaque (sample RGBA 233,232,227,253), all image corners have alpha 0, and the image has intermediate alpha for antialiasing/shadows. This is a generative cutout derivative, not a claim of pixel-for-pixel identity with the JPEG. No manual cleanup was applied. Visually checked shield, needle, N/E/S/W, compass ticks, both text lines, padding, and edges on the actual navy splash. No obvious rectangular backdrop, face holes, clipped main logo, or white edge halo was observed at rendered phone sizes.

Extraction prompt: remove only the surrounding pale rectangular background and isolated decorative star outside the logo; preserve shield, compass, N/E/S/W, cyan/green needle, light compass face, BINNACLE and MARINE SYSTEMS, bevels and intentional soft shadows; genuine alpha, clean antialiasing, padding; do not redesign/retype/relight or add CONNECT. The exact imagegen result was copied into the production path.

## SPLASH IMPLEMENTATION

Widget: `flutter_app/lib/ui/widgets/connect_startup.dart`. Integration: `flutter_app/lib/main.dart`, `MaterialApp.builder` around its existing Navigator.

- Immediate full-screen wave image with `BoxFit.cover` and a navy fallback while decoding. Artwork stays outside SafeArea; brand composition stays inside it.
- Responsive image width: minimum of 360 logical pixels, 78% available width and 48% available height; `BoxFit.contain`. Supports portrait and landscape without source cropping.
- Logo and live Flutter `CONNECT` text enter with a 1000 ms opacity fade and 94–100% ease-out scale. Static, narrow cyan edge light improves navy lettering contrast; no heavy scrim, spinner or looping effect.
- CONNECT is uppercase, 18 logical pixels, weight 500, letter spacing 5, pale cyan, local platform sans-serif. No network font dependency for splash text and no tagline.
- Real `PairingService.restore()` starts once when the startup wrapper mounts. Required credential restoration and artwork decoding/minimum timing run concurrently. Restoration failure stays gated with a generic retry UI; private exception details are not exposed. Asset-load errors also allow retry.
- The 3500 ms minimum timer starts after artwork precaching and the next rendered frame. Exit requires both that timer and successful real restoration. Fast initialization waits; readiness longer than five seconds stays gated. No arbitrary future pretends Core readiness.
- Core socket connection and media retrieval retain existing provider behavior. Waiting for Core network reachability is deliberately not required to enter the offline/pairing UI. Future required startup dependencies belong in the same initialization future.
- Existing routed child stays mounted. The gate does not push/replace routes or hardcode My Boat. Input, focus and underlying semantics are blocked until a 400 ms fade completes. Reduced-motion settings skip entrance/exit motion while retaining the minimum. Disposal cancels timers and ignores late completion.
- Existing configuration-error branch stays fail-closed and direct; invalid Core configuration is not hidden behind branding.
- Android native launch/window backgrounds match `#020D1C`; Android 12+ day/night launch themes suppress the default launcher-icon interstitial. The full brand presentation and minimum duration belong to Flutter. Native OS splash time is not counted toward the minimum.
- `pubspec.yaml` explicitly registers only the two production assets; demo footage declaration remains unchanged. Originals are controlled evidence, not runtime assets. No signing configuration changes.

## AUTOMATED VERIFICATION

Pinned Flutter 3.41.4 / Dart 3.11.1, matching the existing GitHub workflow.

| Check | Observed result |
|---|---|
| `flutter pub get` | PASS; existing lockfile unchanged |
| `dart analyze` | Exit 0; 54 existing info-level lints, no errors/warnings; no findings in new startup code |
| `flutter test` | PASS: 56 tests + one intentionally skipped Core-only test, before the additional route-preservation test |
| `flutter test test/startup_test.dart` | PASS: all 10 tests including the subsequently added route-preservation case |
| Core-mode `live_mode_test.dart` with existing defines | PASS, 1 test |
| Static Connect policy audit | PASS, no findings (Python UTF-8 mode on Windows) |
| Audit broken/fixed fixtures | Expected exit 1 / exit 0 respectively |
| `flutter build web --no-pub` | PASS; existing secure-storage Wasm dry-run and Cupertino font warnings are not splash failures |
| `flutter build apk --debug --no-pub` | PASS; final native-resource rebuild also passed in 15.0 s |
| `git diff --check` | PASS |

Tests cover asset/widget/text presence, 3499 ms retention, completion after minimum + readiness, slower readiness, retry after failure, blocked taps, disposal during initialization, reduced motion, route preservation and initialization not restarting on route changes, and three aspect ratios. Fake-clock pumps verify timing; no wall-clock sleeps. Real image decoding is isolated from the fake clock. Existing app navigation tests warm assets before mounting the app, preventing unrelated Google Fonts network work from running inside image-decoding test zones.

## EMULATOR/RENDER VERIFICATION

These are actual Flutter widget renders, not mockups or physical screenshots. The evidence run loads the Flutter SDK's Roboto font into the test's sans-serif family so test-only Ahem boxes do not substitute for CONNECT. Command: `flutter test test/startup_test.dart --dart-define=SPLASH_EVIDENCE=true`, with `FLUTTER_ROOT` set to the pinned SDK.

- [412 × 915 portrait](splash_412x915.png) — tall-phone/S25-like logical aspect ratio; exported at 2×.
- [360 × 640 portrait](splash_360x640.png) — compact phone; exported at 2×.
- [915 × 412 landscape](splash_915x412.png) — landscape; exported at 2×.

Inspected centering, scale, compass face/markings, alpha edges, readable lettering and CONNECT, wave visibility, dark central space and lack of clipping/overflow. Background cover intentionally crops more of the portrait wave in landscape. No emulator was used. Widget renders do not verify Samsung system-bar behavior or GPU timing.

## PHYSICAL DEVICE VERIFICATION

**PHYSICAL_DEVICE_VALIDATION_PENDING**. `adb devices -l` returned an empty device list. No install, launch, system-bar inspection, background/resume, or on-device timing test is claimed for this change. Prior BIN-36 acceptance applies to the earlier APK only. Target remains Samsung Galaxy S25 Ultra SM-S938U, Android 16/API 36, arm64-v8a, One UI 8.5.

Production signing and real Core end-to-end acceptance remain outside this splash issue and open under existing program work.

## Defects found and corrected

- No startup readiness gate existed: credential restoration was fire-and-forget. Added an awaited presentation gate and visible retry without replacing provider/routing architecture.
- Navy logo lettering lacked separation on navy: added a restrained static edge light without recoloring the foreground asset.
- Android's inherited launch window could flash white/default icon: matched native navy backgrounds and Android 12+ themes.
- Initial test render used Ahem blocks for CONNECT: evidence-only real font loading corrected it.
- First image-decoding test harness exposed unrelated Google Fonts HTTP errors: prewarm branding before app mounting in navigation tests, preserving existing production font behavior.
- Initial callbacks used duplicate underscore names unsupported by the repository language version: corrected and verified compilation.

Final local debug APK SHA-256: `78a85d84194427040f6abb3deaae16d3867423cf62c6f67b9b2802cf01185d31`. Both packaged branding assets were extracted from the APK and matched production bytes. Focused analysis of the new widget/tests reports no issues.

## Delivery addendum

Remote commit/PR/CI and program-record reconciliation are pending at this evidence draft. No merge or remote success is claimed by this draft. Updates below will reference verified remote results, keeping physical validation separate.
