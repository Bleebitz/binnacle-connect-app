# Connect — Landscape Live Camera Console: acceptance record

Date: 2026-09-18. Branch `bin-connect-landscape-camera-console`, stacked on
`bin-connect-demo-media-controls` (PR #13, still open at the time of writing).

> **This landscape Demo experience demonstrates local recorded-demo media
> interaction and forward-compatible Connect UX. It is not evidence that real
> Vision/Core Snapshot, Highlight, physical camera ePTZ, rider-selection
> authority, or Jetson integration has been accepted unless separately verified
> against the real system.**

History is preserved: the earlier Demo camera and media-controls evidence stays in
[`CONNECT_DEMO_CAMERA_ACCEPTANCE.md`](CONNECT_DEMO_CAMERA_ACCEPTANCE.md).

## Approved requirement

Portrait stays the normal Connect app. Rotating the phone horizontally while on
Live becomes a purpose-built, full-screen Binnacle riding camera console: video
first, big touch targets, one-handed use, fast Zoom / Snapshot / Highlight, clear
Track state, a minimal always-visible status HUD, and an honest Demo-vs-Core
boundary. Google/Pixel Camera was a usability reference only; the design is
Binnacle-native.

## Design and behaviour (as implemented)

| Area | Behaviour |
|---|---|
| Orientation | Landscape + Live tab active → console; back to portrait → the unchanged Live screen. The Live tab is only "active" while selected, so other tabs in landscape are unaffected. |
| State across rotation | One `GlobalKey`'d `EptzVideoView` is *moved* between the portrait card and the console, so the `VideoPlayerController` is never rebuilt. Presentation state lives in `LandscapeConsoleController` owned by the Live screen; domain state stays in `DemoZoom`, `DemoRiderLock`, `VisionTrackState`, `DemoRecordedCameraSource`, `ControlChannelService`, `ClipRepository`. |
| Full screen | Bottom navigation hidden while the console shows; `SystemUiMode.immersiveSticky` (edge swipe still reveals system bars); `SafeArea` for the cutout/insets; a large back arrow always leaves the console (to My Boat). |
| Keep awake | `FLAG_KEEP_SCREEN_ON` through a 16-line `binnacle/screen` method channel in `MainActivity` (no dependency, no permission), cleared on exit/dispose. |
| Layout | Right thumb zone: 96 dp **SAVE HIGHLIGHT** (shutter-sized, ring pulse on save), 64 dp Snapshot, broadcast **status** chip (status only, no fake control), and a zoom column (+, 1×/2×/3×/4×, −). Left: back, view-mode selector, Rider Lock, Clean View, telemetry toggle. Video is shown whole (`BoxFit.contain`) so no rider is cropped by the display. |
| Minimum HUD (never fades) | Demo label, Track state, lock state, playback/rec state, link state, zoom, and the highest-priority warning (buffer degraded/recovering, Core link lost). The MOB banner is included above everything. |
| Auto-hide | ~3 s idle fades the non-critical controls (and makes them non-tappable); any pointer-down, pinch, control use, capture, or picker/HUD use restores and restarts the clock. A tap on unused video restores. |
| Clean View | Button, or a downward swipe in the video area (ignored for pinches, sideways drags, and swipes that start in the top system strip). Keeps only the feed, Demo label, Track, lock, and rec state, plus any warning; drops the link and zoom chips. A tap leaves it. |
| Zoom | **(The centre pivot below was rejected by Levi and replaced; see the evening revision.)** Pinch, +/−, presets 1×–4×, double-tap = 1× ↔ last magnified level (not a fixed 2×). Demo: local digital transform of the video only (`Transform.scale` inside a clip), max 4.0×; **no `nudge_zoom`**. Core: unchanged `nudge_zoom` (presets/double-tap are computed as a delta from the Core's zoom); no local transform and no local pinch. |
| Snapshot | Uses the real Demo Snapshot from PR #13 (frame at the player's position). Flash, haptic, "Snapshot saved to Library", a 112×64 thumbnail bottom-left for 5 s; tapping it opens that item in the Library. The video keeps playing. Failure shows the error and creates nothing. |
| Highlight | Uses the real Demo Highlight from PR #13. Ring animation, haptic, and the message reports the *actual* window, e.g. "Highlight saved · 15s before / 30s after", and the clamped numbers near the start/end. Playback is not paused or seeked. |
| Demo timeline | Thin bar at the bottom, drag or tap to seek the **video player**; the position shown is what the player reports. Track state, Snapshot and Highlight read the same clock. Real Live shows a rolling-buffer status line and no seeking. |
| Rider Lock | **(Superseded by the 2026-09-18 evening revision below: rejected by Levi.)** Demo: a picker of two **simulated** targets ("not detections"); the selection shows a lock icon and a `LOCK · SIM` chip. Core: no target data exists, so the picker says "Not available yet" and the chip reads `LOCK · N/A`. Architected as `DemoRiderLock` + `ConsoleBindings.lockTargets` so Track can supply real targets later. |
| RAW / TRACK FOLLOW / MANUAL | **(Superseded below.)** Demo: local overlay modes only (no ePTZ is performed by a recorded video). Core: TRACK FOLLOW / MANUAL send `set_control_mode` (ai/manual); RAW is disabled because Core has no such mode. |
| Telemetry panel | Speed, rider distance (marked *simulated* in Demo), camera state; wake/rider metrics and battery are shown as *unavailable*. Nothing invented. |
| Demo/Core | The Demo label and the "simulated locally" wording stay; vessel controls (presets, arm, trigger, orientation) are not exposed in Demo. Core mode gets none of the Demo behaviour (tested). |

## Deliberate limitations of this pass

*(Superseded by the 2026-09-18 evening revision below, which replaced the simulated picker and centred reticle.)*

- Rider Lock uses **simulated** targets in a picker, not boxes over people. The
  recorded clip has no per-frame detector output, and drawing boxes at fixed
  screen positions would misrepresent the footage. Real target boxes need Track.
- `RAW`, `TRACK FOLLOW` and `MANUAL` change overlays only in Demo.
- Core-mode landscape is covered by tests only; it was **not** run against a real
  Core/Vision (none is attached).
- The reticle is a centred presentation overlay (as in portrait), not a
  source-coordinate box, so it does not scale with the video.
- Landscape Library/detail sheets use the existing layout and need scrolling.

## Source files

New: `lib/ui/screens/landscape_camera_console.dart`,
`lib/ui/screens/landscape_console_controller.dart`,
`test/landscape_console_test.dart`, `test/support/screen_size.dart`.
Changed: `lib/ui/screens/capture_screen.dart` (layout switch, bindings, chrome),
`lib/ui/widgets/eptz_video_view.dart` (fit / pinch / label options),
`lib/core/services/camera_media_source.dart` (position notifier, seek, view mode,
rider lock), `lib/core/services/demo_media.dart` (`DemoZoom.toggleReset`,
`DemoViewMode`, `DemoRiderLock`), `lib/main.dart` (hide nav, tab wiring),
`lib/ui/screens/library_screen.dart` (open-by-id request),
`MainActivity.kt` (keep-awake channel), and the portrait tests that relied on
Flutter's 800×600 default surface (now landscape) so they request a portrait
phone explicitly (`test/live_mode_test.dart`, `test/widget_test.dart`,
`test/capture_demo_controls_test.dart`).

## Automated results

- `dart analyze` (the CI command): **exit 0**, 0 errors, 0 warnings, 58
  info-level lints of existing style (checked with the real exit code and a
  count of `error`/`warning` lines, not a filtered grep).
- `flutter test`: **160 passed, 3 skipped** (the skips are the existing
  mode gates plus the new Core-only tests, which run under the Core define).
- Core-mode regression (`flutter test test/live_mode_test.dart` with the
  `core` defines, as in CI): **2 passed** (the original test plus a new Core
  landscape test: no Demo label, no timeline, no simulated lock, no bottom nav).
- `connect_audit.py` static audit: pass; audit self-test: pass.
- New `landscape_console_test.dart` covers orientation and the same video
  element surviving 3 rotation cycles; auto-hide, restore and idle-clock reset;
  Clean View by button and swipe, and swipes that must *not* trigger it; pinch,
  +/−, presets, clamps, double-tap toggle to the *previous* zoom; Demo zoom
  sending no Core command and Core zoom sending `nudge_zoom`; Snapshot (position,
  thumbnail, Library routing, failure); Highlight (window, near start/end, not
  seeking, failure); timeline seek driving Track/Snapshot/Highlight and no
  seeking in real Live; Rider Lock (Demo simulated, Core unavailable); view
  modes; shell navigation; and the controller.

## Samsung Galaxy S25 Ultra (SM-S938U, Android 16) — observed

Installed in place with `adb install -r` (no uninstall, no data clear):
`versionCode` 2013 → 2014 → **2015**; `firstInstallTime` 2026-09-16 14:24:00
unchanged. Rotation was driven with the system rotation setting (`adb shell
settings put system user_rotation`), which was restored afterwards
(`accelerometer_rotation=1`, `user_rotation=0`).

- **APK** `flutter_app/build/app/outputs/flutter-apk/app-release.apk`
  (190,700,940 bytes), SHA-256
  `9d26597e63a59ef18bcf110395786081ffd520a617b36bd4e34315be614ce73a`
  (debug-signed test build, as in the established workflow).
- Screenshots in `docs/evidence/landscape-console/` (01–14). 02–04, 05, 07–10
  were captured on build 2014; 06, 11, 12, 13 and 14 on build 2015. The 2015
  build differs from 2014 only by the Clean View chip trim and moving the
  thumbnail clear of the left buttons.

| Check | Observed |
|---|---|
| Portrait Live unchanged | Yes (`01`) |
| Rotate to landscape → console appears automatically, full screen, no navigation bar | Yes (`02`) |
| Back to portrait → normal Live and navigation | Yes |
| Repeated portrait↔landscape (3 cycles + a 4th landscape) | Video kept playing: the progress bar advanced ~8 s per cycle, consistent with wall-clock time; no restart to 0:00 was seen |
| Both landscape orientations | Yes (`user_rotation` 1 and 3; the HUD insets adapt) |
| Auto-hide after ~3 s, minimum HUD stays | Yes (`02`); note that the first tap only restores hidden controls, by design |
| Tap restores controls | Yes (`03`) |
| Zoom preset 2× makes the rider visibly larger; HUD/buttons do not scale; chip reads 2.0× | Yes (`04`) |
| Snapshot: confirmation, thumbnail, tap opens the real image in the Library | Yes (`05`, `06`, `07`) |
| Highlight: "Highlight saved · 15s before / 30s after"; video not paused | Yes (`08`) |
| Highlight appears in the Library as DEMO, plays | Yes (`13`); a saved 1:05–1:50 clip matched a press at ~1:20 |
| Timeline tap seeks; Track state follows (2:05 → "OCCLUDED · COASTING") | Yes (`09`) |
| Snapshot position matches the console clock | Partly: a Snapshot taken with the console at 0:18 appears in the Library as `Snapshot — 0:17`. A Snapshot taken right after a timeline seek (console 1:08) was made, but its Library label was **not** checked, so "Snapshot uses the seeked position" is covered by automated tests only |
| Rider Lock picker; selected target obvious; labelled simulated | Yes (`10`) |
| Clean View by button, and by an adb downward swipe; only the essentials remain; state survived rotation | Yes (`11`, `14`) |
| Screen stays on in the console, released on exit | Yes: a `SCREEN_BRIGHT_WAKE_LOCK` held by this app was present in the console and gone after leaving it |
| Saved media survives the 2014→2015 upgrade | Yes (`12`), with real thumbnails and DEMO badges |
| Crash / ANR | None in the crash buffer or logcat (`FATAL EXCEPTION`, `ANR in`) |

## Not verified on the device (stated exactly)

- **Pinch in landscape**: adb cannot inject a two-finger touch; pinch was verified
  by Levi by hand in the portrait Live view (see the Demo acceptance record) and
  by automated gesture tests in the console. Not observed in landscape.
- **Double-tap zoom toggle**: two adb taps cannot be made to land inside the
  300 ms window, so it was not observed on the phone (automated test only).
- Presets 3× and 4×, zoom −, the 1× preset, and the telemetry panel were not
  exercised on the phone (2× and +/− behaviour are covered by tests).
- Camera-cutout overlap was checked visually in both orientations (no chip is
  clipped) but not with a measured inset comparison.
- Memory growth, audio duplication, TalkBack, bright-sun contrast, low storage
  and long soak were not tested. No black or frozen video was observed.
- Everything Core/Vision (real Track targets, real ePTZ, `set_control_mode`,
  `nudge_zoom` on a real vessel) is untested against real hardware.

## Before this UI can run against the real Jetson/Vision/Core stack

Core must supply per-frame Track targets and a rider-selection command, a RAW
framing mode, and a WebRTC/WHEP feed whose Track state and timing are proven
(BIN-51); the console's Core branches then need a device pass. A real Live
rolling-buffer read-out needs the Core buffer fields. Broadcast controls belong to
BIN-38.

---

## Revision — 2026-09-18 (evening): rider-aware Track Follow and on-video Rider Lock

**This revision supersedes the Rider Lock, RAW/TRACK FOLLOW/MANUAL, zoom-centre and
"Deliberate limitations" statements above.** The original text is kept as history
because that is what was first built and first reviewed.

> **This landscape Demo experience demonstrates local recorded-demo media
> interaction and forward-compatible Connect UX. It is not evidence that real
> Vision/Core Snapshot, Highlight, physical camera ePTZ, rider-selection
> authority, or Jetson integration has been accepted unless separately verified
> against the real system.** The rider box in this revision is a *pre-authored
> spatial annotation of the controlled recorded footage*. It is not live
> detection, AI inference, Jetson tracking, or Core Rider Lock. BIN-51 stays open.

### Levi's physical review of the first landscape build (versionCode 2015/2016)

Direct observations on the Samsung Galaxy S25 Ultra:

| Item | Levi's result |
|---|---|
| Pinch-to-zoom in landscape | **PASS** |
| Double-tap zoom in landscape | **PASS** |
| Post-seek Snapshot Library label | **PASS** |
| 3× and 4× controls | Function, **but zoom was fixed on the centre of the image, not the wakesurfer. Rejected** as unacceptable for Track Follow |
| Rider Lock | **Rejected.** It was a simulated picker, the reticle was in the centre of the screen, and it did not lock onto the rider in the footage |
| Deletion (PR #15 build) | Levi deleted all 21 accumulated Snapshots/Highlights from the Connect Library successfully |

That feedback caused this revision. The first implementation was not rider-aware.

### Root cause (confirmed)

`EptzVideoView` zoomed with `Transform.scale(alignment: Alignment.center)`, a
pivot that knows nothing about the rider. The Track overlay was a centred
`ProximityReticle`, and the Demo Rider Lock model (`SimRiderTarget`) held only an
id and a label, with no box, coordinates or per-time position. Nothing in the app
could locate the wakesurfer, so nothing could follow or mark them.

### What changed

- **Spatial annotation, not a detector.** `flutter_app/assets/demo/gopro_dev_rider_track_v1.json`
  (68 KB): a versioned track for the exact controlled footage
  (`assets/demo/gopro_dev_footage.mp4`, SHA-256
  `6815ded40dd19e8e4a0cf1db2c30b7eb9e04585029bc64d935c5c76ffdf33f8f`,
  1920×1080, 30 fps, 130 s, 82,092,098 bytes; verified before use). Boxes are
  **normalised source-frame coordinates** (centre and size, 0..1), never screen
  pixels, so the data is independent of portrait/landscape, resolution, safe
  areas, BoxFit and zoom. No computer-vision package was added to the app.
- **How it was made** (dev tooling in `tools/demo_track/`, not shipped):
  1. Frames were extracted with ffmpeg (exact-frame seeks; OpenCV seeking was not
     frame-accurate on this file) and the wakesurfer's whole-body box (head to
     board) was read off full-resolution crops with a pixel grid.
  2. **53 hand-read keyframes** (every ~2–3 s, denser through the fall) cover the
     pass. Where passengers hid the rider's legs the box was set by eye, not by
     the tracker.
  3. Between keyframes the rider weaves ~100 px sideways per second, so OpenCV's
     CSRT tracker (dev-only) was run between each pair of hand-read boxes and its
     centre error was spread back linearly, so the result **equals the hand-read
     box at every keyframe and cannot drift**; sizes come from the hand-read
     boxes. This gives **495 visible boxes at 0.25 s spacing**, plus **2 occluded**
     keyframes and **1 unknown** keyframe (498 in all).
  4. The shipped result was drawn over exact frames every 2 s across the whole
     pass (`docs/evidence/rider-track/dev-overlays/`) and reviewed; boxes were
     corrected until each surrounded the wakesurfer.
- **States.** Visible through 123.5 s; **occluded** 123.6–129 s (last-known box,
  drawn dashed and labelled `COASTING`, never as a detection); **unknown** from
  129 s (no box at all). The Track-state chip and box style agree
  (`ACQUIRING` → amber candidate box; `TRACKING` → white; locked → teal
  `RIDER LOCKED`; `OCCLUDED · COASTING` → dashed).
- **Model.** `TrackTargetState` (target id, label, `NormBox`, visibility,
  provenance, optional role) is the contract real Binnacle Track can later fill;
  `TargetProvenance` marks Demo annotation vs Core. The Demo's targets are
  labelled Demo; `LiveWebRtcCameraSource.targets` stays **empty** (with an
  `acceptTargets` hook for real Track output only) and never fabricates one.
- **One geometry for pixels, box and taps.** `FramingGeometry` (source size,
  viewport, BoxFit cover/contain, zoom, focus) computes the video matrix, the
  box's screen rectangle, and tap hit-testing, so they cannot disagree. The focus
  is clamped so **no empty canvas or black strip is ever exposed**.
- **Track Follow** (`TrackFollowFramer` + `DemoFraming`): a central safe zone
  (12% × 14% of the visible window) lets the rider drift without moving the crop;
  outside it the crop pans just enough to hold the rider at the zone's edge, with
  exponential smoothing (τ = 0.22 s: no jumps, no overshoot, no drift). The zone
  is never larger than the room the box leaves in the window, so a box that fits
  is never allowed out of view. When the box outgrows the window at tight zoom the
  crop holds the **upper body** (about 32% down the box) so the head and torso stay
  and the lower legs are cropped. A seek, a loop, a zoom change, or switching
  back to Track Follow **snaps** to the rider instead of panning across from the
  old place.
- **Modes.** RAW: centre framing, no rider box, no follow. TRACK FOLLOW: follows
  the annotated rider. MANUAL: pinch zoom and one-finger drag pan (clamped to the
  video); the box stays visible; nothing follows. (The Clean View swipe is not
  offered in MANUAL because a one-finger drag pans there; the button still works.)
- **Rider Lock is on the rider.** The fake `PERSON 2` and the side picker are
  gone. Tapping the rider box locks it (teal, `RIDER LOCKED`, `LOCK · SIM` chip);
  the lock button clears/re-locks; a coasting box cannot be locked. The lock is a
  local Demo confirmation, never a Core/Track lock.
- **Single clock.** The rider box and crop use the same playback position as the
  video, Track state, Snapshot, Highlight and timeline. `video_player` reports
  its position every 100 ms, so `DemoPlaybackClock` extrapolates *from that report*
  between polls (so the box moves every frame) and adopts the player's value
  immediately after any seek or loop. It is not a second timeline.
- **Clean View** keeps the rider box (it is drawn on the video, not with the
  controls), Track state, rec status, Demo label and warnings.
- **Portrait** uses the same geometry and box (the old centred reticle is gone for
  the recorded Demo); Core keeps whatever Core supplies, currently nothing.

### Automated tests

`dart analyze` (CI command): exit 0, 0 errors, 0 warnings (63 infos, existing
style). `flutter test` on this branch: **252 passed, 3 skipped**; Core-mode
regression: **2 passed**; audit and audit self-test pass. New and changed:

- `rider_track_test.dart` (36): parses the real asset; tied to the source SHA/size;
  0..1 validation and rejection of bad data; exactly one target (no second
  person); keyframes return their own box; smooth interpolation that stays between
  keyframes; no interpolation across occluded, unknown or large gaps; seeks are
  stateless; loop/reset returns the start state.
- `track_framing_test.dart` (36): BoxFit mapping; overlay, video matrix and tap
  agree at 1–4×; reverse landscape equals landscape; left/right/top/bottom edges
  and no black exposure over the whole pass at every zoom in landscape and portrait;
  the rider stays in the middle of the crop at 2×, 3×, 4× through the entire pass;
  1× makes no extra pan; safe-zone hold, smooth monotone pan with no overshoot,
  seek/loop/zoom snapping; a box that fits never leaves view; RAW, MANUAL,
  manual pan clamp, MANUAL→TRACK FOLLOW reacquire; the playback clock.
- `landscape_console_test.dart` (extended): tapping the rider box locks; tapping
  elsewhere does not; the tap area follows the box after the crop pans; clear and
  re-lock; a coasting box cannot be locked; no target after the fall; no
  `PERSON 2` and no picker; presets 2×/3×/4× keep the rider framed; pinch and
  double-tap do not lose the rider; a timeline seek moves box and crop at once;
  MANUAL/RAW; Clean View keeps the indication; `DemoFramedStage` draws the box
  where the transformed rider pixels are.
- `core_target_boundary_test.dart` (5) and `live_mode_test.dart`: Core never loads
  the Demo track, never gets boxes, has no Demo lock, no timeline; Demo follow-pan
  and lock send no `nudge_zoom` or any Core command.

### Samsung Galaxy S25 Ultra (SM-S938U, Android 16), observed

In-place `adb install -r` (no uninstall, no data clear), `versionCode` 2016 → 2017 →
2018 → 2019 → 2020 during iteration; `firstInstallTime` unchanged. Screenshots:
`docs/evidence/rider-track/s25/`.

| Check | Observed |
|---|---|
| Rider box on the actual wakesurfer at 1× (two different positions) | Yes (`01`, `05`) |
| Tap the box → teal `RIDER LOCKED` + `LOCK · SIM`; clear; re-lock by tap; no Person 2 | Yes (`02`, `07`) |
| 2× frames the rider | Yes (`05`) |
| 3×: rider boxed and framed at 0:10, 0:30, 0:54, 1:19, 1:39, 1:56 | Yes (`03`); the label sits below the HUD |
| 4×: rider framed at 0:20, 1:04, 1:31, 1:51 | Yes (`04`). At 4× the source window is only ~270 px tall while the rider is 300–400 px, so the crop shows head and torso and crops the lower legs; the head can touch the top edge |
| Seeks (timeline taps to 0:10 … 1:56) put the box and crop on the rider immediately | Yes; no slow pan across from the old place was seen |
| Fall: locked at 2:00, then dashed `COASTING` last-known box with `OCCLUDED · COASTING` | Yes (`06`) |
| RAW hides the box and centre-frames; MANUAL holds the crop, one-finger drag pans, the box stays on the rider's pixels | Yes (`07`) |
| Snapshot after a seek reads `Snapshot — 1:11` (seek ≈ 1:10) | Yes (`08`, `09`) |
| No black strips at any zoom; no crash or ANR | None seen |

### Not verified on the device (stated exactly)

- **Pinch and double-tap after this framing change were not re-tested on the phone**
  (adb cannot inject them; Levi verified both on the previous build). Covered by
  automated tests only. Please re-check by hand.
- The "no target" state after 129 s was not captured on the device (the seek lands
  ~2:07); it is covered by tests.
- Any residual offset between the box and the video frame from display latency was
  not measured; at 3–4× a fast-moving rider can sit slightly off the box for a
  frame or two.
- Nothing here was run against a real Jetson/Vision/Core. Real rider selection,
  real Track boxes, real ePTZ and BIN-51 remain unverified.

### Still required before this runs against the real stack

Binnacle Track must emit `TrackTargetState`-shaped targets (id, normalised box,
visibility, provenance, optional role) and accept a select/lock command; the Core
must expose them; `LiveWebRtcCameraSource.acceptTargets` gets its adapter; and
Track-state timing over WebRTC (BIN-51) must be proven. Multiple targets (rider,
passenger, swimmer, another boat) then need real detections; none are fabricated
here.
