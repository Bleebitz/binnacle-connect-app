/// Compile-time feature flags.
///
/// Spotter AI biometric embeddings are OFF unless explicitly compiled in, and
/// must never be switched on for consumer data without documented legal
/// sign-off (docs/legal/README.md). CI (`biometric-guard`) blocks any change
/// that flips this default or sets it to true in a tracked build file.
const bool kSpotterBiometricsEnabled =
    bool.fromEnvironment('SPOTTER_BIOMETRICS', defaultValue: false);
