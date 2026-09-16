# Samsung Galaxy S25 Ultra Device Acceptance

**Test date:** 2026-09-16
**Repository:** https://github.com/Bleebitz/binnacle-connect-app
**Branch:** `bin-android-s25-apk`
**Source commit SHA:** `9ce428e` (fix commit, on top of `524d24e`/`a146498` — see "Rebuild" section below for why)
**Related Linear issues:** BIN-35, BIN-36, BIN-32

This is a physical-device first-launch acceptance test only. It does not prove real Core connectivity, real Vision/Track telemetry, real WebRTC, or real media playback — see Limitations.

## Summary

The first install (from the original BIN-35 artifact, checksum `d790412...`) revealed a real, reproducible UI layout defect on the Live tab. Per instructions, this was reproduced, fixed with the minimum justified change, the app was rebuilt with a new checksum, reinstalled, and the failed check was repeated and now passes. **Final result reflects the rebuilt artifact** (checksum `bbb4793...`), not the original one.

## DEVICE

- **Manufacturer:** samsung (`ro.product.manufacturer`)
- **Model:** SM-S938U (`ro.product.model`) — Samsung Galaxy S25 Ultra, US unlocked variant
- **Android version:** 16 (`ro.build.version.release`)
- **API level:** 36 (`ro.build.version.sdk`)
- **ABI:** arm64-v8a (`ro.product.cpu.abi` / `ro.product.cpu.abilist` — arm64-v8a only, no 32-bit fallback)
- One UI version: 8.5 (`ro.build.version.oneui=80500`)
- Only one device was attached via `adb devices -l` at all times — no ambiguity requiring device selection.
- Device serial number is intentionally **not** recorded here (non-sensitive model/platform info only, per instructions).

## APP / APK IDENTITY

**Original build (superseded):**
- Package ID: `com.binnacleconnect.binnacle_connect`
- Version name / code: `0.1.0` / `2001`
- APK filename: `binnacle-connect-s25-test-arm64.apk`
- APK SHA-256: `d790412572e71324f5479d92896e7483a3d036aca69eb719ee7ddfd9b1593d3b`
- Build type: `release` (Android build type) / **Signing type: debug** (`CN=Android Debug`, cert SHA-256 `5e178b27...`)

**Final build (tested, current):**
- Package ID: `com.binnacleconnect.binnacle_connect` (unchanged)
- Version name / code: `0.1.0` / `2001` (unchanged)
- APK filename: `binnacle-connect-s25-test-arm64.apk` (same name, rebuilt content)
- **APK SHA-256:** `bbb4793025152198bfc50af97742ea04f83326c795fe963ed818e601a6dcc008`
- Build type: `release` / **Signing type: debug** (same certificate as original — confirmed via `apksigner verify --print-certs` after rebuild)
- ABI confirmed `arm64-v8a` only (inspected APK `lib/` contents directly, both builds)

Both builds independently verified with real Android tooling (`aapt dump badging`, `apksigner verify --print-certs`, build-tools 36.1.0) before installation, not assumed from the receipt alone.

## INSTALLATION

- **Install command (original):** `adb install build/app/outputs/flutter-apk/binnacle-connect-s25-test-arm64.apk`
- **Install command (after fix):** `adb install -r build/app/outputs/flutter-apk/binnacle-connect-s25-test-arm64.apk`
- **Install result:** `Success` both times (streamed install). `dumpsys package` confirmed installed `versionName`/`versionCode` matched the APK both times.
- **Existing-install handling:** App was not previously installed (`pm list packages` returned nothing before the first install) — first install was fresh, no existing data. The post-fix install used `-r` (upgrade), which correctly preserved `firstInstallTime` (2026-09-16 14:24:00) and updated only `lastUpdateTime` (2026-09-16 14:31:35) — no uninstall, no data loss, same signing certificate so no signing-incompatibility issue.

## FIRST LAUNCH

- **Launch command:** `adb shell am start -n com.binnacleconnect.binnacle_connect/.MainActivity`
- **Launch result:** App process started (confirmed via `pidof`), became the resumed/focused activity (confirmed via `dumpsys activity activities` / `dumpsys window`).
- **Expected first screen rendered:** Yes — "My Boat" screen, matching the app's intended front door. **PASS**
- **Immediate crash:** NO
- **ANR:** NO
- **Layout usable on S25 Ultra:** **PARTIAL on the original build** (Live tab: `SIMULATED` badge overlapped the `16:9 · 1080p` HUD tag, illegible) → **PASS on the rebuilt/fixed build** (confirmed via a new screenshot, both badges render as distinct legible lines)
- **Navigation smoke test:** **PASS** — tapped through My Boat, Live, Session, Library, Community (and Community's Crew/Sessions sub-tab); also incidentally reached the Pairing screen's unclaimed-unit ownership-warning dialog and backed out cleanly via its "Stop" control without claiming ownership. Process PID never changed across any of this — no crash at any point.

## PERMISSIONS

- **Permissions requested:** App manifest declares `CAMERA` (runtime/dangerous) and `INTERNET`/`ACCESS_NETWORK_STATE`/`WAKE_LOCK`/`MODIFY_AUDIO_SETTINGS`/a self-scoped broadcast-receiver permission (all normal/install-time).
- **Permission behavior:** `CAMERA` showed `granted=true` **before** any in-app interaction that would trigger a runtime prompt (`dumpsys package` immediately after install). This is consistent with Android/Samsung retaining a prior permission grant for this exact package name + signing certificate from earlier development installs on this same device — **not** something this test session granted, and not evidence of the natural request flow being exercised. The QR-pairing camera screen (where a real runtime request would occur for a device with no prior grant) was not navigated to in this session.
- **Problems:** None observed. No permission-related crash or loop.

## NO-CORE / OFFLINE BEHAVIOR

- **Result:** Truthful. This APK was built without `BINNACLE_APP_MODE=core` (default demo mode) — the app never attempted any live Core connection, consistent with `app_config.dart`'s documented demo-mode contract.
- **Confirm whether any simulated/demo data appeared:** Yes — simulated telemetry (speed reading, wake trace graph), simulated capture-armed state, simulated buffer status on the Live tab.
- **Confirm whether simulated/demo data was clearly identified:** Yes. My Boat shows "Binnacle connected: Simulated — no Vision device paired," "Vision online: Vision readiness not reported," "Track ready: Track readiness not reported," "Not recording: Awaiting capture," "Who's riding: Automatic rider ID needs Track — not available yet," and an explicit footer: *"Demo mode — nothing above is a real connection. See Settings for details."* The Live tab's video viewport shows a `SIMULATED` badge (illegible before the fix, clearly legible after). No fabricated "connected"/"live"/"recording" state was observed anywhere.

## BACKGROUND / RESUME

- **Background:** **PASS** — sent to background via `KEYCODE_HOME`, process (`pidof`) remained alive both times tested (original build, on the Community screen; fixed build, from the Live screen).
- **Resume:** **PASS** — re-launched via `am start`; Android reported "its current task has been brought to the front" (correct resume behavior, not a relaunch); UI state was pixel-identical to before backgrounding in the original-build test (screenshots `connect_after_stop.png` → `connect_resumed.png`); same PID confirmed on the fixed-build test.

## LOGCAT / RUNTIME

- **Fatal exceptions:** None for `com.binnacleconnect.binnacle_connect`, on either build. Searched for `FATAL EXCEPTION`, `Process: com.binnacleconnect`, `AndroidRuntime`, `ANR in` across the full session logcat — the only `Caused by:` matches were unrelated system services (`DCU_ContactsLogService`, `keystore2`).
- **Flutter exceptions:** One non-fatal, caught exception on both builds: `google_fonts` attempted to fetch `JetBrainsMono-Medium` and `JetBrainsMono-Bold` from `fonts.gstatic.com` at runtime and failed with `SocketException: Failed host lookup`. Caught by Flutter's error handling (`dart_vm_initializer.cc`), did not crash the app or block rendering — those specific font weights likely fell back to a system default. **This is a real, pre-existing behavior of the `google_fonts` package fetching over the network rather than bundling font assets, unrelated to the layout fix in this session** — flagging it here as observed, not fixing it under BIN-36 (out of scope: not a crash, not a block-on-use issue, and not something this task's minimal-change mandate covers).
- **AndroidRuntime issues:** None.
- **Native/ABI issues:** None — `nativeloader` log confirms `arm64-v8a` native libraries (including WebRTC) resolved and loaded without error.
- **Networking/security issues:** The `google_fonts` DNS-lookup failure above. No TLS/certificate errors.

## SAMSUNG-SPECIFIC OBSERVATIONS

- The layout-overlap defect was found via this physical S25 Ultra test, but its cause is not Samsung-specific — both `Positioned` offsets were hardcoded near-identically in the Dart source and would collide on any screen size/density. Physical testing is simply what surfaced it.
- Edge-to-edge / display-cutout handling: status bar icons and the bottom navigation bar both rendered without clipping around the S25 Ultra's punch-hole cutout and rounded corners (1080×2340).
- No One UI-specific battery-optimization, background-restriction, or Bluetooth-permission dialog was observed during this test — but see Limitations: this was not a scenario specifically designed to trigger those.
- The device's screen locked (timeout) between adb commands more than once during testing, requiring the tester to physically unlock it before a screenshot could show real content instead of the lock screen. This is normal Android/Samsung power behavior, not an app defect, and is not something this session's adb access could or should bypass.

## LIMITATIONS

Not tested in this session (explicitly out of scope for a basic first-launch/lifecycle test per instructions — deferred to full BIN-32 physical acceptance):

- Real Core integration, authenticated pairing, or Core-issued credentials
- Real WebRTC connection / real video stream from a Vision unit
- Real Vision/Track telemetry
- Real Library media (Core clip catalog fetch, playback, download, share) — no Core-backed catalog was available
- On-water / real boating functionality
- The QR-pairing camera runtime-permission *request* flow specifically (camera permission was already granted from prior device history, not exercised fresh in this session)
- Permission-denial behavior
- Extended sleep/reconnect, AP restart, certificate-failure, or expired-credential scenarios
- Notification permission flow (not observed being requested in demo mode on first launch)
- iOS — not applicable to this task

No claim is made about any of the above. This result only covers: the exact rebuilt APK installs, launches, renders its first screen correctly, survives basic navigation and one background/resume cycle without crashing, and truthfully represents its offline/demo state.

## FINAL ACCEPTANCE RESULT

**S25_FIRST_LAUNCH_PASS**

The originally-received BIN-35 artifact (`d790412...`) showed a real, non-blocking UI defect on first physical inspection (Live tab badge overlap) — correctly a **PARTIAL** result at that point, not silently passed over. It was reproduced, fixed with the smallest justified change (`flutter_app/lib/ui/screens/capture_screen.dart`, commit `9ce428e`), the automated test suite was re-run clean (`dart analyze` 0 errors/warnings, `flutter test` 47/47), the APK was rebuilt and re-verified (new SHA-256 `bbb4793...`, same package/version/ABI/signing identity), reinstalled as an upgrade over the existing install, and the failed check was repeated and now passes. The **final, currently-installed artifact** on this device meets every PASS criterion: correct S25 Ultra confirmed, exact rebuilt-artifact checksum verified before and after install, successful install, matching package/version identity, successful launch, correct first screen, no crash or ANR, working navigation smoke test, working background/resume, truthful offline/no-Core representation, and this controlled evidence committed to the repository.

This result proves only that the controlled Connect APK installs and reaches a stable first-launch state on Levi's Samsung Galaxy S25 Ultra. It does not constitute the broader Connect/Core physical acceptance under BIN-32.
