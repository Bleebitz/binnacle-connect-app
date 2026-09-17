plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.binnacleconnect.binnacle_connect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.binnacleconnect.binnacle_connect"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// 16 KB page-size compatibility (investigated 2026-09-17, real S25 Ultra device
// finding on Android 16 — see docs/evidence/CONNECT_SPLASH_BRAND_ASSET_ACCEPTANCE.md).
//
// Only two bundled native libraries were confirmed genuinely misaligned via
// `llvm-readelf -l` (ELF LOAD segment p_align, not zip-entry alignment):
//   - lib*/libimage_processing_util_jni.so — from androidx.camera:camera-core,
//     pulled in transitively by mobile_scanner's hardcoded camera-camera2/
//     camera-lifecycle:1.3.3. Fixed upstream in CameraX 1.4.0+; forced below.
//   - lib*/libbarhopper_v3.so — from com.google.mlkit:barcode-scanning /
//     play-services-mlkit-barcode-scanning, also pulled in by mobile_scanner.
//     NOT fixed upstream as of this investigation even at the latest
//     17.3.0 (see https://github.com/googlesamples/mlkit/issues/989) — no
//     16 KB-aligned build of this native library exists yet to force. Left
//     as a known, documented limitation rather than suppressed.
// The other libraries the on-device OS dialog listed (libflutter.so,
// libdartjni.so, libjingle_peerconnection_so.so, libVkLayer_khronos_validation.so)
// were verified via the same ELF inspection to already be aligned at 16 KB or
// 64 KB — the dialog's "Unknown error" for those is a false positive from the
// OS's debug-build compatibility checker, not a real alignment failure.
configurations.all {
    resolutionStrategy {
        force(
            "androidx.camera:camera-camera2:1.4.2",
            "androidx.camera:camera-lifecycle:1.4.2",
            "androidx.camera:camera-core:1.4.2",
        )
    }
}

flutter {
    source = "../.."
}
