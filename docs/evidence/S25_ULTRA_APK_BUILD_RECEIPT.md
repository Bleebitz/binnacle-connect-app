# Samsung Galaxy S25 Ultra — Binnacle Connect APK build receipt

**Date:** 2026-09-16
**Repo:** https://github.com/Bleebitz/binnacle-connect-app
**Branch:** `bin-android-s25-apk`
**Commit SHA:** `524d24e246606ca1019a87ca6d072324d3fed689`
**Product:** Binnacle **Connect** (phone/cloud companion app). This is not Spotter (the separate physical display product) — no vessel-control or Spotter functionality was added or touched.

No source code was changed to produce this build. This receipt documents an APK build only.

## Stack and config as inspected

- **Stack:** Flutter (Dart), Android via the standard Flutter Gradle plugin. Not native Android, not React Native.
- **Flutter version:** 3.41.4 (pinned in `.fvmrc`; matches the toolchain in `flutter_app/android`).
- **Application ID:** `com.binnacleconnect.binnacle_connect`
- **SDK levels (Flutter 3.41.4 defaults, not overridden in `build.gradle.kts`):** compileSdk 36, targetSdk 36, minSdk 24.
- **Signing:** `flutter_app/android/app/build.gradle.kts`'s `release` build type explicitly sets `signingConfig = signingConfigs.getByName("debug")` (with a `TODO: Add your own signing config for the release build` comment already in the file). **No release-signing configuration exists in this repo.** No production keystore/credentials were created or invented for this build, per instructions.
- **ABI:** no ABI filters set in `build.gradle.kts`; an unsplit `flutter build apk --release` produces a fat APK containing `armeabi-v7a`, `arm64-v8a`, and `x86_64` (confirmed by inspecting a first build's `lib/` contents before discarding it). `--target-platform android-arm64` alone did **not** reduce this — the resulting APK still contained all three ABIs, most likely because at least one plugin's native library packaging isn't restricted by that flag alone in this Flutter version. `--split-per-abi` (Flutter's standard per-ABI splitting mechanism) was used instead and reliably produced an arm64-v8a-only artifact, verified below.
- **Existing CI** (`.github/workflows/ci.yml`) already builds an unsplit `flutter build apk --debug` and `flutter build apk --release` on every push, both green as of this commit. This build is additional, arm64-only, and local — it does not change CI.

## Samsung Galaxy S25 Ultra compatibility

- S25 Ultra ships Qualcomm Snapdragon 8 Elite — **arm64 (arm64-v8a) only**, no 32-bit ARM. An arm64-v8a-only APK is the correct, sufficient artifact; it deliberately excludes `armeabi-v7a` and `x86_64`.
- S25 Ultra ships Android 15 (API 35), upgradeable to Android 16 (API 36). minSdk 24 / targetSdk 36 / compileSdk 36 are all compatible — a device running API 35 or 36 satisfies minSdk 24 with margin, and targeting API 36 is the current API level, not ahead of it.
- Manifest permissions: `INTERNET`, `CAMERA` (both declared and justified in `AndroidManifest.xml` comments), plus `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `MODIFY_AUDIO_SETTINGS`, a self-scoped `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, and `BLUETOOTH` (`maxSdkVersion=30`, so it does not apply on the S25 Ultra's API 35/36 at all) — all pulled in by dependencies (WebRTC/media/scanner plugins), none legacy-storage, SMS, contacts, or anything else likely to fail or prompt unusually on a modern Samsung device. Nothing was added or removed from the manifest for this build.
- No security settings were lowered to make the build succeed.

## Build

**Command:**
```
flutter clean
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64
```

**Build type:** `release` (Android build type — R8/shrinking applied), **signed with the debug keystore** (see Signing above). This is a locally-signed test build, not a Play-Store-ready release.

**Result:** `flutter_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`, copied byte-for-byte to the requested filename below (checksums match — see Verification).

## Verification performed

| Check | Result |
|---|---|
| APK exists | Yes |
| File size | 37,529,843 bytes (~35.8 MB) — non-zero, reasonable for a Flutter app with WebRTC/video/camera plugins |
| Application ID | `com.binnacleconnect.binnacle_connect` (via `aapt dump badging`) |
| Version name / code | `0.1.0` / `2001` — see note below |
| Supported ABI | `arm64-v8a` only, confirmed by listing every `lib/<abi>/` directory inside the APK zip (no `armeabi-v7a`, no `x86_64`) |
| APK parseable by Android tooling | Yes — `aapt dump badging` (build-tools 36.1.0) parsed the manifest, permissions, and version info without error; `apksigner verify --print-certs` (build-tools 36.1.0) verified the signature and printed the debug certificate |
| Build completed with no fatal errors | Yes — Gradle `assembleRelease` succeeded (86.3s) |
| Automated tests | `flutter test`: **47/47 passed** (no code changed since the last full green run on `main`) |
| Lint / static analysis | `dart analyze`: **0 errors, 0 warnings**, 54 pre-existing info-level style suggestions (`prefer_const_constructors` and similar), none new, none touching this build |

**Version code note:** `versionCode=2001` is not a real version bump — Flutter's `--split-per-abi` applies a per-ABI offset to the base build number (pubspec `0.1.0+1` → base build number `1`) so ABI-specific APKs of the same release can coexist in a store listing. `versionName` (`0.1.0`) is the real, unaffected app version.

**Signing detail:** `apksigner verify --print-certs` reports:
```
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
Signer #1 certificate SHA-256 digest: 5e178b27681264ff787d8509848f77cf58e77f3040a2d22b1ff7c14426a73caa
```
This is the standard Android debug keystore certificate — confirms the "debug-signed" classification above is accurate, not assumed.

## Artifact

- **APK filename:** `binnacle-connect-s25-test-arm64.apk`
- **APK output path:** `flutter_app/build/app/outputs/flutter-apk/binnacle-connect-s25-test-arm64.apk` (local build output only — `build/` is gitignored and this file is **not** committed to the repository; it was also sent directly to the user)
- **SHA-256:** `d790412572e71324f5479d92896e7483a3d036aca69eb719ee7ddfd9b1593d3b`
- **Signing:** debug / test (see above) — not a production release signature

## Known limitations

- No release-signing configuration exists in this repo. This build cannot be distributed via Play Store or any channel requiring a real release signature.
- `--target-platform android-arm64` alone did not exclude other ABIs in this Flutter version/plugin combination; `--split-per-abi` was required to get a genuine arm64-only artifact. Anyone reproducing this build should use the exact command above, not `--target-platform` alone.
- This build was not exercised against a real Core backend or real Vision/Track hardware — see `README.md`'s "Status, stated honestly" section for the app's existing, broader limitations (unrelated to this APK build itself).
- No device-specific testing beyond static APK verification was performed (see below).

## Physical device installation

**No Android device was connected to this machine.** `adb devices -l` returned an empty device list. Per instructions, physical installation, launch, and device-specific verification were **not attempted** and are **not claimed**.

**APK_BUILD_VERIFIED_READY_FOR_S25_INSTALL**
