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

**[Superseded for zoom, snapshot, and highlight by the 2026-09-18 revision at the end of this document; kept here as history.]**
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
- Static analysis (as recorded for the original Demo camera commit, before the
  2026-09-18 media-controls work; that later work introduced warnings that CI
  caught, see the 2026-09-18 Tests section): 0 errors and 0 warnings; 53
  existing info-level lints remained.
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

## Revision — 2026-09-18: Demo Snapshot, Save Highlight, and local Zoom enabled

**This section supersedes the earlier statement that Recorded Demo Mode disables
zoom, snapshot, and highlight.** That statement is kept above unchanged as
history; the paragraph below explains why it existed and why it changed.

**This demonstrates local recorded-demo media interaction only. It is not evidence
that real Vision/Core Snapshot, Highlight, or camera ePTZ has been integrated or
accepted.**

### Owner feedback and root cause

The owner physically tested the demo build on the Samsung Galaxy S25 Ultra
(`versionCode=2012`) and reported that Zoom, Snapshot, and Save Highlight
could not be used on the recorded Live feed.

This was not an Android touch bug. `capture_screen.dart` deliberately passed
`null` for `onZoomIn`, `onZoomOut`, `onSnapshot`, and `onHighlight` whenever
`AppConfig.isDemo`, so the buttons rendered disabled. The original rationale was
sound for what existed then: those controls were Core commands, and a recorded
video has no vessel or Vision unit to command, so the safe choice was to disable
them rather than imply a hardware action. What was missing was a distinction
between **media-view actions**, which a recorded feed can honestly simulate
locally, and **Core/Vision actions**, which it cannot.

### Revised policy

| Action | Recorded Demo Mode | Core Mode (unchanged) |
|---|---|---|
| Zoom `+` / `−` / pinch | **Local digital zoom** of the recorded video | Core `nudge_zoom`, Core-authoritative |
| Snapshot | **Local**: a real frame of the recorded video | Core `snapshot`, waits for acknowledgement |
| Save Highlight | **Local**: a segment reference into the bundled asset | Core `save_highlight`, waits for acknowledgement |
| Presets, manual/AI orientation, trigger mode, arm/disarm, broadcast | **Disabled** (vessel/Core actions) | Core commands |

The persistent `DEMO — RECORDED CAMERA FEED` label remains. No Core command is
sent by any local Demo action, and no Core acknowledgement is claimed.

### Implementation

- **Provenance.** `Clip` gained `origin` (`core` | `demoSegment` |
  `demoLocalCapture`), `segment`, and `localPath`, so demo media is never
  disguised as a Core `mediaUrl`. Core JSON parsing is unchanged and can only
  ever yield `core` origin. Demo clips carry a `DEMO` badge in the Library and a
  provenance panel in the detail view. The bundled showcase clip is now also a
  segment (0:00-2:10) instead of an `assets/` string in `mediaUrl`.
- **Zoom** (`DemoZoom`). 1.0x to 4.0x in 0.5x steps, plus a two-finger pinch
  (`DemoPinchZoom`). The maximum is 4.0x, not the product's 6.0x, because the
  source is 1920x1080. It scales only the video (`Transform.scale` inside the
  viewport clip); tags, buttons, and the HUD are siblings and stay put. Core
  Mode keeps `nudgeZoom` and the Core's own zoom value.
- **One clock.** The video player registers itself with
  `DemoRecordedCameraSource`; its real position drives Track state, Snapshot,
  and Save Highlight. There is no second timer. Capture before the player is
  ready fails with a message rather than inventing a position.
- **Snapshot.** The playback position is read fresh from the player. An Android
  method channel (`binnacle/demo_media`, `MainActivity.kt`) decodes that frame of
  the bundled asset with `MediaMetadataRetriever` (`OPTION_CLOSEST`) and writes
  a 1920x1080 JPEG to app-owned storage (`getApplicationDocumentsDirectory()/
  demo_media/`). It is also published to `Pictures/Binnacle/` through
  MediaStore (scoped storage, API 29+). No FFmpeg, no screenshot of the video
  texture, and no storage permission: the APK declares only `INTERNET`, `CAMERA`,
  `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `MODIFY_AUDIO_SETTINGS`, and the app's own
  receiver permission (checked with `aapt` and `dumpsys`). An empty or missing
  image is an error, never a "saved" message.
- **Save Highlight.** `HighlightWindow` takes the playhead, the demo pre-roll
  (15 s) and post-roll (30 s), and clamps to `[0, 130 s]` (minimum 1 s). The
  saved clip is a `MediaSegment(assetPath, start, end)`; **no video is copied**.
  Library playback opens the bundled asset, seeks to `start`, plays, and stops
  and rewinds at `end`. A real frame from the capture point is saved as the
  thumbnail (best-effort).
- **Persistence.** Demo-origin clips are stored as JSON in
  `shared_preferences` (image files stay in app storage). Missing image files
  are dropped on restore; corrupt entries are ignored; the showcase seed clips
  are never persisted. Nothing is persisted in Core Mode.
- **Copy.** The notice now reads: "Recorded demo feed — Snapshot, Highlight, and
  digital Zoom are simulated locally. Vessel controls remain disabled."

### Tests

`dart analyze` (the CI command) exits 0: 0 errors, 0 warnings, 60 info-level
lints of existing style. **Correction:** the first push of this branch failed
CI's `dart analyze` on 3 `unnecessary_cast` warnings in my zoom-column code. My
earlier local check used a filter that missed them, so my earlier statement of
"0 warnings" was wrong. Fixed in `1795815`; the release APK built from the
fixed tree is byte-identical (same SHA-256), so the device evidence below
applies to it. The Core-mode regression run, `flutter build web`, and the audit
self-test also pass locally (the self-test needs `python3` on PATH).
`flutter test`: 129 passed, 2 skipped by existing mode gates. New coverage:

- `demo_media_logic_test.dart` (22): zoom steps and clamping, highlight window
  mid-source / near start / near end / on the last frame / out-of-range /
  zero-roll, `m:ss` labels, local JSON round-trips, malformed-record rejection,
  a local record can never claim Core origin, Core JSON ignores demo fields,
  Demo-vs-Core type separation, and the video position as the single clock for
  Track state and capture.
- `demo_media_capture_test.dart` (14, real files): snapshot writes a real file
  at the requested position with Demo provenance; extractor failure and an empty
  file are errors with no file left behind; gallery-export failure keeps the
  in-app snapshot; a highlight is a segment reference with no video written;
  clamping near start and end; thumbnail failure is non-fatal; restart
  persistence, missing-file handling, seed exclusion, favorite persistence,
  no duplicates on repeated hydration, Core-origin rejection, and the
  `shared_preferences` store with corrupt data.
- `capture_demo_controls_test.dart` (7): on the real Live screen the recorded
  label stays, media controls work, vessel controls stay disabled, snapshot and
  highlight land in the Library with the right position and roll, failures show
  an error and save nothing, and a recording control service proves **no Core
  command is ever sent**.
- `demo_pinch_zoom_test.dart` (4): two-pointer pinch in/out, clamping, one
  finger does nothing, pinch continues from the button-set zoom.
- `widget_test.dart`: the Live-tab test that asserted "disables vessel controls"
  now asserts zoom responds, the new notice appears, the old wording is gone,
  and the Arm switch stays disabled.

### Samsung Galaxy S25 Ultra evidence (observed)

Device `SM-S938U`, Android 16. Installed as an in-place upgrade:
`adb install -r`, `versionCode` 2012 to **2013**, `firstInstallTime`
(2026-09-16 14:24:00) unchanged, signature `3678f22f` unchanged, no uninstall or
data clear. Screenshots are in `docs/evidence/demo-media-controls/` (status bar
cropped off).

| Step | Observed |
|---|---|
| Launch, Live tab, 130 s rider pass plays | Yes (frame-to-frame motion measured) |
| `DEMO — RECORDED CAMERA FEED` visible | Yes |
| Zoom `+` visibly enlarges the video; label `1.0×`, `1.5×`, `2.0×` | Yes. At 2.0x the horizon and rider move as expected for a centre crop; tags, buttons, and HUD do not scale |
| Zoom back to `1.0×` with `−` | Yes |
| Pinch zoom | **Not verified by me or by adb.** Later verified by hand by Levi on the same phone, see the 2026-09-18 manual acceptance addendum below |
| Snapshot: flash, toast "Snapshot saved to Library and Photos" | Yes |
| Library shows the actual captured frame | Yes. The two gallery copies are 1920x1080 JPEGs whose best match to frames extracted from the asset is source second 117 and 23, the positions the Library reports (`1:57`, `0:23`) |
| Save Highlight: toast "Highlight saved to Library"; new Highlight in Library | Yes (`0:11–0:56`, `0:17–1:02`, `0:00–0:45`: the last is the start clamp) |
| Highlight plays from its start point | Yes. `0:17–1:02` showed `0:01 / 0:45`, `source 0:17–1:02`, and its first frame matched source seconds 17–20 (not 0 or 60) |
| Highlight stops at its end | Yes, on both the earlier and the final build. About 50 s after Play it is paused and rewound to `0:00 / 0:45` and stays there; it did not run on through the 130 s source |
| Force-stop and relaunch: saved media remains | Yes, with the real thumbnails and DEMO badges; also survived the APK reinstall |
| Crash / ANR | None in the crash buffer, `FATAL EXCEPTION`, `ANR in`, or Flutter error log |
| Dangerous storage permission | None declared or granted; no `MANAGE_EXTERNAL_STORAGE` |

Evidence files: `01_live_1.0x.png`, `02_live_2.0x.png`,
`03_snapshot_confirmation.png`, `04_highlight_confirmation.png`,
`05_library_saved_snapshot_and_highlight.png`,
`06_highlight_playback_start.png`, `07_highlight_stopped_at_end.png`,
`08_library_after_restart.png`.

### Build

- Branch: `bin-connect-demo-media-controls` (from `bin-connect-demo-camera-simulation`
  at `54e134a`).
- Implementation commit: `48bfab0cd277a2acf28c92908984133d61427f04`, plus the
  analyzer fix `1795815ee846c1de5358034a089cc082f6779dd9` (APK bytes identical
  before and after the fix).
- `flutter build apk --release --build-number=2013` (debug-signed, as in the
  established device workflow; not production-signed).
- APK: `flutter_app/build/app/outputs/flutter-apk/app-release.apk`, 190,618,268
  bytes, SHA-256
  `8BDBCF375993C0202BA300F3E47A223352BF82A2E27D96A2B1EFB61147244785`.
- The controlled demo asset was not modified: SHA-256
  `6815DED40DD19E8E4A0CF1DB2C30B7EB9E04585029BC64D935C5C76FFDF33F8F`, identical
  before and after.

### Limitations and observations (stated exactly)

- **Local simulation only.** Nothing here proves Core/Vision Snapshot, Highlight,
  or ePTZ, the real Jetson/WebRTC control path, or Core-authoritative zoom.
  Core Mode's `snapshot`, `save_highlight`, and `nudge_zoom` paths were not
  changed and were not exercised on a device.
- **Pinch could not be verified by adb** (superseded by Levi's manual check, see addendum below). Injecting a two-finger touch needs
  write access to `/dev/input/event8`, which the adb shell user does not have
  (`Permission denied`), and `adb shell input` has no pinch. The handler is
  covered by 4 automated two-pointer gesture tests.
- **Zoom maximum is 4.0x**, not the product's 6.0x, because the source is 1080p.
  Snapshots are the **full source frame**; they are not cropped to the zoomed
  view.
- **Highlights are references, not files.** They play only inside the app and
  cannot be shared or downloaded. A standalone MP4 would need an explicit export
  step, which is not implemented.
- **Snapshot latency.** The toast appears after the frame is decoded, typically
  under about a second; the source has a keyframe roughly every 8.3 s.
- **Accumulation.** *(Superseded by the 2026-09-18 deletion addendum below.)* There was no delete for demo media. Testing left about ten
  Demo items in the phone's Library and two project-owned demo frames in
  `Pictures/Binnacle/`; the gallery copies remain after uninstall.
- **Android only.** Frame extraction is a platform channel; other platforms show
  an error toast.
- **Unexplained observations, not reproduced.** (1) A Demo highlight
  `1:53–2:10` was saved at 15:37:31 without a button press I can account for.
  The only code path that creates a Demo highlight is the SAVE HIGHLIGHT tap, and
  a control experiment (accessibility dumps and a 20 s wait, no taps) created
  none; a person touching the phone is possible. (2) Once, the Live video looked
  frozen for about 10 seconds. Four controlled trials (fresh launch, after
  Snapshot, after Highlight, after tab switch and accessibility dumps) all showed
  continuous motion.
- **Formatting.** The repository's existing Dart files are not `dart format`
  clean at HEAD, so formatting was applied only to new files to keep this diff
  reviewable.
- Not tested: TalkBack, landscape, long-running soak, or low-storage behavior.

### Addendum — 2026-09-18: manual physical acceptance of pinch-to-zoom

**User-observed physical-device acceptance, not an automated test and not
something I observed.** Levi manually tested pinch-to-zoom on the Samsung Galaxy
S25 Ultra (`SM-S938U`) running the installed build below and confirmed that pinch
zoom works correctly. This is Levi's report; no screenshot or recording of the
gesture was captured, and the exact zoom levels reached were not recorded.

- Build under test: `versionCode` 2013, APK SHA-256
  `8BDBCF375993C0202BA300F3E47A223352BF82A2E27D96A2B1EFB61147244785`.
- The later source cleanup (`1795815`, removal of 3 `unnecessary_cast`
  warnings) rebuilt to a byte-for-byte identical APK (same SHA-256, same size
  190,618,268 bytes). The cleanup therefore did not alter the accepted Android
  binary, and the earlier physical evidence applies to it unchanged.
- CI for PR #13 head `8879f12edf35d2ba3fddfbf926576854e08e6a4c` is green: `dart
  analyze`, `flutter test`, Core-mode regression, `flutter build web`, audit
  and audit self-test, debug and release APK builds (run 35399915406).
- Scope: this verifies the Connect Demo's local pinch-to-zoom of the recorded
  feed only. It is not evidence of real Vision/Core physical ePTZ.

### Addendum — 2026-09-18: safe deletion of local Snapshots and Highlights

**Discovered in review.** Levi found on the Samsung Galaxy S25 Ultra that saved
Highlights and Snapshot pictures in the Connect Library could not be deleted. The
missing delete had been listed above as a known limitation ("no delete for demo
media"); it is now a fixed review finding, with the original limitation text kept
as history.

**Root cause (confirmed in code).** `ClipRepository` only had add, hydrate,
favorite and persist operations, and the Library detail sheet offered Favorite,
Download and Share only. There was no remove operation, no persisted-metadata
removal, and no owned-file cleanup. The device was not at fault.

**Semantics.** *Delete from Binnacle*, for a user-created Demo Snapshot or
Highlight:

| Item | Removes | Never touches |
|---|---|---|
| Snapshot (`demoLocalCapture`) | the Library record, its persisted metadata, and Binnacle's own JPEG (`demo_media/snapshot_*.jpg`; `localPath` and `thumbnailPath` are normally the same file and are deduplicated) | the copy the Snapshot exported to the phone's Gallery (`Pictures/Binnacle/`), which **may remain** and is *not* an orphan bug |
| Highlight (`demoSegment`) | the Library record, its persisted metadata, and its generated `_thumb.jpg` if any | the bundled `assets/demo/gopro_dev_footage.mp4` (a Highlight is only a reference into it) |

- **Confirmation** (the destructive action is never one tap): "Delete snapshot?"
  / "This removes the snapshot from Binnacle and deletes its local Binnacle copy.
  A copy saved to your phone's Gallery may remain." and "Delete highlight?" /
  "This removes the saved Highlight from your Binnacle Library. The recorded Demo
  source footage will not be deleted." Buttons Cancel / Delete. Success closes the
  sheet and shows "Snapshot deleted" / "Highlight deleted"; failure shows
  "Couldn't delete this item. Try again." and keeps the item.
- **Safe file deletion.** All deletion goes through `DemoMediaStorage`
  (`lib/core/services/demo_media.dart`), which only ever deletes a *regular file
  strictly inside* the app's `demo_media` directory. It refuses paths outside it,
  `..` traversal, the directory itself, sibling directories that share a prefix,
  directories and symlinks, and the bundled asset key. Persisted metadata is
  treated as untrusted. A missing file is not an error.
- **Repository API.** `ClipRepository.deleteClip(id)` returns a
  `DeleteClipResult` (`deleted`, `deletedCleanupIncomplete`, `notFound`,
  `notDeletable`, `persistenceFailed`). It persists the removal *first*: if that
  fails the item is put back, no file is touched, and the UI says so. If the
  record is gone but an owned file could not be deleted, the item stays deleted
  and the orphan is reported (logged), not restored. The same call is what a future
  bulk delete would use.
- **Protected items.** Built-in `seed-*` showcase clips are not deletable (they
  regenerate on every launch); their sheet says why. **Core clips are not
  deletable**: no authoritative Core delete contract exists, and hiding one
  locally while implying it was deleted would be dishonest. Demo deletion is not
  evidence of real Core/Vision media deletion.
- **Also fixed.** The Library detail sheet had a hidden height cap (9/16 of the
  screen) and no scrolling, which could clip the bottom action row. It now takes
  the height it needs and scrolls on short screens.
- **Future.** "Delete from device too" would need the Snapshot's MediaStore URI to
  be persisted on the clip and deleted through a MediaStore request; it is not
  implemented and no storage permission was added (still no
  `MANAGE_EXTERNAL_STORAGE`).

**Automated tests.** `dart analyze` (CI command): exit 0, 0 errors, 0 warnings
(58 infos, existing style). `flutter test`: **187 passed, 3 skipped**. New:
`test/demo_media_delete_test.dart` (19: path safety, dedup, missing files, `..`
traversal, prefix siblings, directories, bundled asset never deleted, delete
Snapshot/Highlight, restart does not resurrect, unknown id, seed protection, Core
clip protection, persistence failure with order preserved, cleanup failure,
corrupt metadata, no gallery-delete call) and `test/library_delete_ui_test.dart`
(8: Delete shown for Snapshot/Highlight, hidden for Core, built-in note, exact
dialog wording, Cancel, confirm closes the sheet and removes the card, hero
promotion, failure message). Core-mode regression run, audit and audit self-test
pass.

**Samsung Galaxy S25 Ultra (SM-S938U), observed.** In-place `adb install -r`,
`versionCode` 2015 → **2016**, no uninstall, no data clear. APK
`flutter_app/build/app/outputs/flutter-apk/app-release.apk` (190,782,920 bytes),
SHA-256 `5c322c152cd03c9fd46ac9fdd4c9fd5f56f0eed9294ca7826738a25b2b102783`; the
APK installed on the phone hashes identically. Screenshots:
`docs/evidence/media-delete/`.

| Step | Observed |
|---|---|
| Create a Snapshot and a Highlight on Live, both appear in the Library | Yes (`01`) |
| Snapshot detail shows a separated trash icon | Yes (`02`) |
| Confirmation dialog with the Gallery-copy wording | Yes (`03`) |
| Cancel keeps the item | Yes (the sheet and item remained) |
| Delete: sheet closes, card gone, "Snapshot deleted" | Yes (`04`) |
| Highlight plays, then Delete asks with the source-footage wording | Yes (`05`, `06`) |
| Highlight card disappears; the next item becomes the hero | Yes |
| Force-stop and relaunch: neither deleted item returns | Yes (`07`) |
| Demo feed still plays after deletions (frame difference measured), +/− zoom, Snapshot and Highlight still work | Yes |
| Crash / ANR | None seen |

**File-level check (diagnostic build).** A release build is not debuggable, so
the app-owned folder cannot be read on it. For this one check I installed a
*debug build of the same source* over the app (same package, data kept), ran a
controlled before/after with `adb shell run-as`, then reinstalled the release
build. `app_flutter/demo_media` held 20 files; after creating one Snapshot and one
Highlight it held 22 (`snapshot_*.jpg` and `highlight_*_thumb.jpg` added); after
deleting both through the UI it held 20 files again, **identical to the first
listing** (`docs/evidence/media-delete/demo_media_listing.txt`). The earlier
delete of Snapshot `0:14` had likewise left no `17:53` file behind. The bundled
demo footage kept playing.

**Gallery copy.** The exported copies of deleted Snapshots are still in
`Pictures/Binnacle/` (checked with a MediaStore query, for example
`Binnacle_Demo_1789775862817596.jpg`, the Snapshot deleted in the controlled
check). This is the approved behaviour and is stated in the dialog.

**Not verified.** Deleting while a Highlight is playing in the same sheet was not
attempted; the Highlight was deleted from a freshly opened sheet. Very large
Libraries, low storage and TalkBack were not tested. Pinch zoom was accepted by
hand earlier (see above) and not re-tested here. The two non-reproduced
observations recorded earlier (an extra Highlight save, one brief frozen video)
did not recur, and are still not resolved.

