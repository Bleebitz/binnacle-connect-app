# Connect Cloud, Media & Live — Acceptance Evidence

Branch: `bin-37-cloud-media-live` (built on `main` at `19a0193`, after PR #9).
Scope: BIN-37's client-reachable work — Library media import, Community's
Post a highlight, and finishing/reusing BIN-38's Live destination-selection
surface (PR #5).

> **Round 2 update (2026-09-18): sections 1-5 below are the first pass and are partly superseded by section 6.** The "Posted to Crew" / "Publish" wording in section 1 was inaccurate: that action is a local, phone-only session entry and is now labelled "Save to Crew sessions". The screenshot `s25_posted_to_crew.png` shows the old wording. Nothing on any device was sent to another person or a service.

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

## 6. Round 2 — verified result (build 2010)

Legend: **WORKS (device)** = driven on the S25 Ultra with project-owned test
media; **WORKS (test)** = automated tests with fakes, not a real backend;
**BLOCKED** = no underlying service exists.

### 6.1 "Post to Crew" — what it actually does (device-verified)
| Question | Finding |
|---|---|
| Survives app restart? | **Yes.** Entry saved, app force-stopped and relaunched: Community → Crew → Sessions still shows "Today — 1 highlight saved on this phone" (`11_crew_after_restart.png`). Before this round it was in-memory only and was lost on restart; `CrewRepository` now persists riders, sessions and unsent drafts locally (SharedPreferences). |
| Media playable after restart? | Yes — the Library entry points at an app-private file that persists (Library entries and their files survive restart; the edited copy played, see 6.3). |
| Visible only on this phone or to other crew? | **Only this phone.** There is no account, membership, or sync service. No other crew member can receive it. |
| Audience enforced by a backend? | **No.** The only audience is "Crew sessions on this phone (not shared)"; Public is disabled with the real reason. |
| Wording | Renamed "Save to Crew sessions"; the confirmation says it was saved on this phone only and not sent to crew members. |

Real shared Crew publishing depends on authenticated backend storage,
membership and access enforcement (BIN-46, BIN-40, BIN-41/48).

### 6.2 Instagram
Sources: Meta's Instagram Live Producer page (about.instagram.com — "limited
access", instagram.com only; issues a URL + stream key that changes each
session, used as a Custom RTMP destination) and Meta's Instagram Platform
content-publishing docs (images, videos, reels, carousels, stories; live
video is not a listed publishable type). Account eligibility beyond "limited
access" is not stated on the pages consulted, so none is claimed. UI text is
now: **"Instagram streaming is not supported by this implementation."**
Connect has no Live Producer or Graph API integration and promises none.
(`12_connect_live_destinations.png`)

### 6.3 Highlight editor (device-verified with `BINNACLE_TEST_clip.mp4`, 12 s, generated locally)
- Trim 0:03–0:09 (range sliders), Square framing with crop-position slider,
  cover frame, preview, **Save as edited copy** produced a **separate 6 s
  file** (2,624 KB) while the original stays (4,850 KB) — confirmed in
  Storage. Playback of the copy starts at the cut (frame timecode ≈6.3 s of
  source inside a 6 s clip). Audio track and rotation are copied.
- Export is a **lossless trim** via Android MediaExtractor/MediaMuxer (no
  GPL/FFmpeg). The start snaps to the previous keyframe. Progress %, Cancel
  (native side deletes the partial file), an insufficient-space check
  (needs source size + 8 MB free), and missing-source / unsupported-format
  errors are implemented.
- **Not baked into the file:** portrait/landscape/square crop stays an edit
  definition applied at playback (a crop requires re-encoding). An edited
  copy is therefore *not* a standalone cropped video for sharing.
- Not device-tested: the cancel path, the insufficient-space path, and a
  portrait-source orientation. Those are code-reviewed only.
- Screens: `04_editor_square.png`, `05_edited_playing.png`.

### 6.4 Storage management
`06_storage.png`: real per-file sizes (this phone 9.6 MB, 5 items), awaiting
upload, "Confirmed stored remotely: none", Core storage "not available".
Delete = remove the app copy only, with confirmation; no cloud delete exists
(no cloud) and the phone-gallery original is never touched. Fix this round:
deleting an entry no longer removes a file another Library entry still uses.

### 6.5 Requirement tracker (not "complete because UI exists")
| Requirement | Status |
|---|---|
| Offline upload queue: persistence, states, pause/resume/cancel/retry, Wi-Fi/cellular preference, duplicate guard, failure reasons | **WORKS (test)** — state machine and persistence covered with a fake uploader. **BLOCKED for real transfer** (no upload service; production `NoOpMediaUploadService`). Settings → Uploads on device (`07_settings_uploads.png`). No background execution: uploads only run while the app is open. |
| Basic highlight editor | **WORKS (device)** — trim / cover / preview / exported copy; framing playback-only (6.3). |
| Pre-stream check | **WORKS (test)** — blocking/advisory logic, real HTTP timing. On device it is unreachable because no destination can be linked (BIN-46). No broadcast was started. |
| Privacy / sharing controls | **BLOCKED** — needs accounts + backend (BIN-40/46). No fake controls added; everything is private on the phone. |
| Storage management | **WORKS (device)** for local; remote/Core rows honestly empty/unavailable. |
| Session organization | **PARTIAL (test)** — manual session assignment with "Unassigned". Not built: date filtering, Library grouping by session/date/rider, favorites filter, manual rider-tag UI in Library. No machine ID inferred. |
| Public Community safeguards (report / block / removal / moderation) | **BLOCKED** — no moderation backend or identity; public publishing stays unavailable. |

### 6.6 Dependency table
| Feature blocked | Exact missing item | Issue | Smallest next step | Proving test |
|---|---|---|---|---|
| Real media upload (queue to confirmed remote) | Deployed private S3 bucket + upload-authorization contract + identity for who may upload. Provider direction is approved (AWS S3/CloudFront/MediaConvert, BIN-48) but nothing is deployed and no contract is final | BIN-48, BIN-41, BIN-46 | Owner decision on account scope (see `CORE_USER_ACCOUNT_API_PROPOSAL.md`) and AWS account/region/spend approval; then an S3 multipart `MediaUploadService` behind the existing interface | Upload the test clip, HEAD the object, compare checksum, mark uploaded only on match; unauthenticated GET returns 403 |
| Authorized playback / share | CloudFront signed URL/cookie issuance + entitlement lookup | BIN-48, BIN-46 | Signed-URL endpoint against a real S3 object | Authorized URL plays; expired/unauthorized URL is blocked |
| Live broadcast to a real destination | Core `request_live_broadcast` implementation; Cloudflare Stream (preferred candidate) live input; provider OAuth linking or a user-entered RTMP key held server-side | BIN-39, BIN-46 | Create a Cloudflare Stream live input + one custom-RTMP destination (needs account/spend approval) | A real test stream reaches the destination; disconnect/reconnect measured. Needs your approval of destination and content |
| Shared Crew / privacy / reactions across devices | Global Rider Accounts (OAuth), Vision-unit entity, ephemeral session tokens, offline handshake — designed in `CORE_USER_ACCOUNT_API_PROPOSAL.md` v2 (Decoupled Identity Architecture); not built; owner decisions in its section 11 | BIN-46, BIN-40 | Phase 0 sign-off, then Phase 1 cloud identity (OAuth + JWKS) | A rider from a different account joins a boat as crew with cellular disabled; a second device sees / does not see content per permission |
| Community moderation | Moderation queue/service, identity to block/report against | BIN-40 (chat/comments deliberately deferred), BIN-46 | Decide moderation owner/process; add a report endpoint | Report creates a queue item; blocked user's content is hidden |
| Core storage telemetry | Core reporting storage stats | Core team | Add a field to the state schema | Value matches Core disk |

Nothing above was assumed absent merely because an endpoint is missing: the
Cloudflare-live / AWS-durable-media direction in the approved architecture
v0.1 is recorded as *preferred candidates, not deployed, not contracted*.

### 6.7 Personal photo
During the previous on-device session one of the user's own photos was
imported into the app. It was not opened, uploaded or captured in evidence.
Nothing has been deleted; removal awaits the owner's answer. Round 2 device
testing used only `BINNACLE_TEST_clip.mp4` (generated with a local tool).

### 6.8 Build / device
Installed before: `versionCode=2009`. Now: `versionCode=2010`, installed with
`adb install -r` over the existing debug-signed install (`firstInstallTime`
unchanged, 2026-09-16 14:24, so data was preserved; no uninstall/clear).
Logcat crash buffer empty. Screenshots: `docs/evidence/media-round2/`.
