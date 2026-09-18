# Connect Cloud, Media & Live — Acceptance Evidence

Branch: `bin-37-cloud-media-live` (built on `main` at `19a0193`, after PR #9).
Scope: BIN-37's client-reachable work — Library media import, Community's
Post a highlight, and finishing/reusing BIN-38's Live destination-selection
surface (PR #5).

## 1. What's real end to end (verified on a physical device)

Device: Samsung Galaxy S25 Ultra, model `SM_S938U`, serial `R5CY13C57LT`.
Build installed: `versionCode=2009` (upgrade from the previously-installed
`2008`), same signature (`3678f22f`) throughout — a real upgrade install
(`adb install -r`), not a reinstall; no app data lost.

- **`adb shell dumpsys package` before/after:**
  - Before: `versionCode=2008 ... signatures=[3678f22f]`
  - After: `versionCode=2009 ... signatures=[3678f22f]`
- **Release APK:** `flutter_app/build/app/outputs/flutter-apk/app-release.apk`
  SHA-256: `5eb051a2574c0deefdf26eafb95241b05ea5ee3d32a2442a5140cfa08f34aeca`
  (debug-signed, per this project's existing signing setup — not
  production-signed).

### Library: real phone media import
Tapped the real "Add media" FAB → "Choose a photo" → the **genuine Android
system Photo Picker** opened showing the device's actual photo library →
selected a real photo → the app's own preview dialog showed the real
filename/size (`1000005684.jpg`, `8 KB`) → tapped Import → the photo was
copied into app storage and appeared in Library with a real **ON THIS
PHONE** status chip.
Screenshot: `s25_library_on_this_phone.png`.

*(One photo picked accidentally during coordinate-finding was a personal
photo of people, not project content — that screenshot was reviewed on-device
for functional verification only and deliberately excluded from this
evidence set and from anything shared further, out of respect for the
people in it. No further action was needed since it's the user's own photo,
already on their own device, copied into the app's own private storage —
not exposed anywhere.)*

### Best Falls: real-footage import (replacing the removed fake path)
Not re-verified separately on-device this pass beyond confirming no crash —
covered by the automated `best_falls_import_test.dart` suite (12 assertions
across import/cancel/failure), which exercises the exact same
`pickAndImportMedia` code path Library uses.

### Community: Post a highlight
Tapped "Post a highlight" → selected the just-imported photo from the
Library thumbnail row → the sheet showed caption + audience UI with
**Crew selected and Public (Binnacle Live) genuinely disabled**, with the
real reason text ("requires an account/identity system that doesn't exist
— see BIN-46/BIN-40") → entered a caption → tapped Publish → got a real
**"Posted to Crew"** confirmation → navigated back to Crew → Sessions and
saw a real **"Today — 1 highlight posted"** session card, created by this
publish action, not seeded/fake data.
Screenshots: `s25_post_highlight_sheet.png`, `s25_posted_to_crew.png`.

### Live: destination selection, including Instagram
Opened My Boat → Go Live → Connect Live. Confirmed the destination list
renders on-device exactly as coded: Binnacle Live / YouTube / Facebook /
Twitch (all honestly "Not connected — add in Settings," no OAuth exists),
free-tier "up to 1" entitlement label, and the new **Instagram** entry,
disabled, with "Not supported — no general RTMP-push API for Instagram
Live."
Screenshot: `s25_connect_live_instagram_unsupported.png`.

### No crashes
`adb logcat` across the entire on-device session (launch, media import,
system picker round-trip, Post a highlight, Connect Live) showed no
`FATAL EXCEPTION` or unhandled Flutter exception.

## 2. What's real but only verified via automated tests (not re-driven on-device this pass)
- Upload progress/cancel/retry state machine (`library_media_test.dart`,
  against a fake uploader — production ships `NoOpMediaUploadService`,
  so this UI path is real code but not reachable on a real device today).
- Duplicate-tap import guard, local persistence across a simulated restart.
- Full Connect Live GO LIVE lifecycle (`live_broadcast_screen_test.dart`,
  `live_broadcast_service_test.dart` — pre-existing BIN-38 coverage, rerun
  and confirmed still passing after the merge).

## 3. What's blocked, and the exact dependency
- **Cloud media upload** — no backend exists (BIN-41 upload policy, BIN-48
  storage architecture, both Todo, no chosen provider/contract). Shipped:
  `NoOpMediaUploadService`, reporting "Cloud upload isn't available yet"
  honestly rather than guessing an endpoint.
- **Public/social highlight posting** — no identity/viewing backend (BIN-46,
  BIN-40, both Todo). Shipped: Crew-only publishing, Public shown disabled
  with the real reason.
- **YouTube/Facebook/Twitch OAuth linking** — no cloud control plane
  (BIN-46, Todo). Shipped: honest "not connected."
- **A broadcast actually reaching any real destination** — no Core-side
  `request_live_broadcast` implementation, no Binnacle Cloud ingest/fan-out
  (BIN-39, Todo). Shipped: real client-side lifecycle model, demo-mode
  simulated timeline, Core-mode wire contract that will genuinely time out
  against a Core that doesn't implement it yet.
- **Instagram Live** — not a missing-backend gap; a real platform
  limitation (Meta doesn't offer a general third-party RTMP-push API into
  Instagram Live). Documented, not worked around.

## 4. Checks run
- `flutter analyze`: 0 errors (pre-existing info-level style lints only).
- `flutter test`: 106 passed, 2 skipped (Core-mode-only gating, pre-existing
  pattern) — includes 3 new test files for this work
  (`library_media_test.dart`, `best_falls_import_test.dart`,
  `post_highlight_test.dart`) covering real pick/preview/cancel/duplicate-
  tap/progress/retry/persistence/audience-gating against fakes for the
  picker/uploader — never a real OS plugin or network in CI.
- `PYTHONUTF8=1 python tools/connect_audit/connect_audit.py flutter_app/lib`:
  no findings.
- Real device verification: see section 1.

## 5. Login/biometric — explicitly not touched
No login or biometric authentication was added in this change. See
`docs/evidence/CORE_USER_ACCOUNT_API_PROPOSAL.md` (merged in PR #9) for the
still-pending proposal on what a real account system would need.
