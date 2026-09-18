import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:binnacle_connect/main.dart';
import 'package:binnacle_connect/core/app_config.dart';
import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/models/credential.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';
import 'package:binnacle_connect/ui/widgets/connect_startup.dart';
import 'package:binnacle_connect/ui/widgets/simulated_wake_view.dart';

import 'support/fake_media_services.dart';

void main() {
  testWidgets('Live mode contains no demo media or simulated video', (tester) async {
    // This test exercises Core mode's My Boat/Live screens, not the splash
    // itself (see test/startup_test.dart for that) — skip it outright.
    ConnectStartup.debugSkipForTesting = true;
    addTearDown(() => ConnectStartup.debugSkipForTesting = false);

    // PairingService.restore() isn't invoked at all with the splash
    // skipped, but this mock stays as defensive insurance against a future
    // codepath that reads secure storage during this test.
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    ConnectivityPlatform.instance = FakeConnectivityPlatform();
    await tester.pumpWidget(const BinnacleConnectApp());
    // A single pump suffices: debugSkipForTesting finishes the splash on
    // the first frame.
    await tester.pump();
    final context = tester.element(find.text('My Boat').first);
    final clips = context.read<ClipRepository>();
    expect(clips.clips, isEmpty);
    expect(find.byType(SimulatedWakeView), findsNothing);
    expect(find.textContaining('Core health unavailable'), findsWidgets);
    expect(() => clips.seedDemo(), throwsStateError);
    expect(() => clips.addFromCapture(kind: ClipKind.photo, preset: 'test'), throwsStateError);
    // Real phone media import (importPicked) is intentionally NOT gated by
    // AppConfig.isDemo — it's the user's own local file, independent of
    // demo/Core mode — so there's no Core-mode-throws assertion for it here
    // (see library_screen.dart's ClipRepository.importPicked doc comment).
    await expectLater(context.read<PairingService>().debugSimulatePairing(
        unclaimed: false, role: DeviceRole.owner), throwsStateError);
    await tester.tap(find.text('Live').last);
    // Fixed duration, not pumpAndSettle(): the offline-state connection dot
    // (see capture_screen.dart's `_PulsingDot(pulsing: status == ... ||
    // status == LinkStatus.offline)`) animates perpetually by design here —
    // this test's whole point is that Core mode with no real Core shows a
    // persistent "offline" indicator, not a transient "connecting" one that
    // settles. pumpAndSettle() would wait forever for it to stop.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Live video unavailable'), findsOneWidget);
    expect(find.text('Telemetry unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: AppConfig.isDemo);
}
