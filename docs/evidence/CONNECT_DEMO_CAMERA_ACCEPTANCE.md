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

Demo Mode autoplays and loops the controlled GoPro clip at
`flutter_app/assets/demo/gopro_dev_footage.mp4`. The original placeholder was
replaced after device review with a 130-second fixed-stern rider pass trimmed
from the owner-supplied `GX010048.MP4` source (source time 09:50–12:00). The
original 11.52 GB source is not committed. The bundled asset is a silent,
1920×1080, 30 fps H.264 High 4:2:0 MP4 (82,092,098 bytes; SHA-256
`6815DED40DD19E8E4A0CF1DB2C30B7EB9E04585029BC64D935C5C76FFDF33F8F`).

The demo feed is persistently marked `DEMO — RECORDED CAMERA FEED`. A pure,
video-position-driven reducer produces `ACQUIRING RIDER` → `RIDER LOCKED` →
`TRACKING`, then aligns `OCCLUDED · COASTING` and reacquisition with the real
fall/loss at the end of the pass. The live source
uses the same state type and begins at `TRACK STATE UNAVAILABLE` until the
Core/Vision Track-state schema is connected; WebRTC status is not misreported
as rider state.

Recorded Demo Mode disables preset, zoom, orientation, snapshot, highlight,
trigger-mode, arm/disarm, and other vessel-control affordances. It also states
that no Vision capture or vessel action is active. Demo Mode retains its
existing no-network guarantee.

## Verification

- Replacement media inspection: the complete 12:48 source was sampled at
  60-second intervals, candidate ride windows were sampled at 10-second
  intervals, and the fall window was sampled at 2-second intervals before the
  09:50–12:00 segment was selected. Final encoded frames at 0, 30, 60, 90,
  120, and 126 seconds confirmed upright orientation, 16:9 crop, continuous
  rider visibility, and the terminal fall/loss event.
- Static analysis: 0 errors and 0 warnings; 53 existing info-level lints remain.
- Flutter tests: 82 passed, 2 intentionally skipped by existing mode/platform
  gates. New coverage verifies Demo/Core source selection, deterministic Track
  reducer boundaries, state publication, the persistent recorded-feed label,
  and disabled vessel controls.
- Android: `flutter build apk --debug --build-number=2012 --no-pub` succeeded
  and produced `build/app/outputs/flutter-apk/app-debug.apk` (298,234,287
  bytes; SHA-256
  `D65675E86042257E44D7733F7211C190469EDFCD576BB24A6337744ECBC2741B`).

## Boundaries preserved

- No frozen Track dataset or evidence file was changed.
- No existing S25 acceptance receipt or acceptance claim was changed.
- No Cloud ownership or publishing workflow was moved into Connect; this work
  is limited to the client-side camera source, playback, HUD, and tests.
- No unrelated repository was modified.

## Samsung Galaxy S25 Ultra deployment follow-up — 2026-09-18

The Demo Camera branch at commit
`4f02db90d07c61e37454f04ddadd1b79559c3617` was deployed to the connected
Samsung Galaxy S25 Ultra (`SM-S938U`, device serial `R5CY13C57LT`). The phone
already contained the same application ID at `versionCode=2010`, so the
verified source was rebuilt with `flutter build apk --debug
--build-number=2011 --no-pub` to permit a normal in-place Android upgrade.
This follows the repository's existing controlled-device build-number pattern;
the package identity and `versionName=0.1.0` remain unchanged.

- Deployed APK SHA-256:
  `626C97A34D469F862AEC4BC5875CC2E1E9C6AC7EBC215E260DCC842F2ECC8851`.
- `adb install -r` result: `Success`; the app was not uninstalled and its data
  was not cleared.
- Post-install `dumpsys package` result: `versionCode=2011`,
  `versionName=0.1.0`, `lastUpdateTime=2026-09-18 13:48:59` local time.
- A cold `am force-stop` / explicit `MainActivity` launch succeeded; Android
  reported `MainActivity` as focused and `pidof` confirmed a running process.

This deployment check proves installation and launch of the new branch build.
It does not add a new S25 acceptance claim for on-screen video playback; that
remains a direct visual/user acceptance observation.

## Replacement-video device deployment — 2026-09-18

The APK containing the owner-supplied 130-second rider pass was installed as
an in-place upgrade on the same Galaxy S25 Ultra. `adb install -r` returned
`Success`; no uninstall or app-data clear was performed. Post-install package
inspection reported `versionCode=2012`, `versionName=0.1.0`, and
`lastUpdateTime=2026-09-18 14:39:03` local time. A cold explicit launch
succeeded, Android reported `MainActivity` as the focused activity, and
`pidof` confirmed the app process was running.

This supersedes the version-2011 APK for device review. It proves packaging,
installation, and launch of the replacement asset; direct on-screen playback
acceptance remains a user observation and is not claimed here.
