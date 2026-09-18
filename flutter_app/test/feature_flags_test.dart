import 'package:flutter_test/flutter_test.dart';

import 'package:binnacle_connect/core/feature_flags.dart';

void main() {
  test('Spotter biometrics default to OFF', () {
    // No --dart-define is passed by the test runner, so this is the production
    // default. A change that flips it must fail here and in biometric-guard.
    expect(kSpotterBiometricsEnabled, isFalse);
  });
}
