# Connect Demo Camera Mode — implementation receipt

**Date:** 2026-09-18

**Repository:** `Bleebitz/binnacle-connect-app`

**Base:** `origin/main` at `19a0193`

**Branch:** `bin-connect-demo-camera-simulation`

## Scope and result

The existing Live camera viewport now accepts a reusable camera media source.
Demo Mode selects a recorded Flutter asset and Core Mode selects the existing
authenticated WebRTC service; the viewport, 16:9 center-crop behavior, HUD,
and Vision/Track state presentation are shared.

Demo Mode autoplays and loops the existing controlled GoPro development clip
at `flutter_app/assets/demo/gopro_dev_footage.mp4`. Its introducing commit
(`437df63`) records that the source was re-encoded to H.264 High / yuv420p and
successfully played on the Samsung Galaxy S25 Ultra. No footage was fabricated
or added for this change. The 12-second container duration was checked so all
four simulated Track phases occur before each loop.

The demo feed is persistently marked `DEMO — RECORDED CAMERA FEED`. A pure,
video-position-driven reducer produces the simulated sequence `ACQUIRING
RIDER` → `RIDER LOCKED` → `OCCLUDED · COASTING` → `TRACKING`. The live source
uses the same state type and begins at `TRACK STATE UNAVAILABLE` until the
Core/Vision Track-state schema is connected; WebRTC status is not misreported
as rider state.

Recorded Demo Mode disables preset, zoom, orientation, snapshot, highlight,
trigger-mode, arm/disarm, and other vessel-control affordances. It also states
that no Vision capture or vessel action is active. Demo Mode retains its
existing no-network guarantee.

## Verification

- Static analysis: 0 errors and 0 warnings; existing info-level lints remain.
- Flutter tests: 82 passed, 2 intentionally skipped by existing mode/platform
  gates. New coverage verifies Demo/Core source selection, deterministic Track
  reducer boundaries, state publication, the persistent recorded-feed label,
  and disabled vessel controls.
- Android: `flutter build apk --debug` succeeded and produced
  `build/app/outputs/flutter-apk/app-debug.apk` (251,101,837 bytes; SHA-256
  `FBFAA5E443E52046C0D092E72C6A207FA501F4E817E4E0B3F1A68B2332EA22E9`).

## Boundaries preserved

- No frozen Track dataset or evidence file was changed.
- No existing S25 acceptance receipt or acceptance claim was changed.
- No Cloud ownership or publishing workflow was moved into Connect; this work
  is limited to the client-side camera source, playback, HUD, and tests.
- No unrelated repository was modified.
