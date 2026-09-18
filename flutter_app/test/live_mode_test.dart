import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:binnacle_connect/main.dart';
import 'package:binnacle_connect/core/app_config.dart';
import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/models/credential.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';
import 'package:binnacle_connect/ui/widgets/connect_startup.dart';
import 'package:binnacle_connect/ui/widgets/simulated_wake_view.dart';
import 'support/screen_size.dart';

void main() {
  testWidgets('Live mode contains no demo media or simulated video',
      (tester) async {
    usePortraitPhone(tester);
    // This test exercises Core mode's My Boat/Live screens, not the splash
    // itself (see test/startup_test.dart for that) — skip it outright.
    ConnectStartup.debugSkipForTesting = true;
    addTearDown(() => ConnectStartup.debugSkipForTesting = false);

    // PairingService.restore() isn't invoked at all with the splash
    // skipped, but this mock stays as defensive insurance against a future
    // codepath that reads secure storage during this test.
    FlutterSecureStorage.setMockInitialValues({});
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
    expect(() => clips.addFromCapture(kind: ClipKind.photo, preset: 'test'),
        throwsStateError);
    expect(() => clips.importFallClip(), throwsStateError);
    await expectLater(
        context
            .read<PairingService>()
            .debugSimulatePairing(unclaimed: false, role: DeviceRole.owner),
        throwsStateError);
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

  // The landscape camera console must not smuggle Demo behaviour into Core
  // Mode: no Demo label, no recorded-source timeline, no simulated targets,
  // and honest "not available" state for Rider Lock.
  testWidgets(
      'Core landscape console shows no demo media, timeline or simulated lock',
      (tester) async {
    useLandscapePhone(tester);
    ConnectStartup.debugSkipForTesting = true;
    addTearDown(() => ConnectStartup.debugSkipForTesting = false);
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pump();
    await tester.tap(find.text('Live').last);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('console-min-hud')), findsOneWidget);
    expect(find.text('DEMO — RECORDED CAMERA FEED'), findsNothing);
    expect(find.byKey(const ValueKey('console-timeline')), findsNothing);
    expect(find.text('LOCK · SIM'), findsNothing);
    expect(find.text('LOCK · N/A'), findsOneWidget);
    expect(find.byType(SimulatedWakeView), findsNothing);
    // The normal bottom navigation is hidden while the console owns the display.
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: AppConfig.isDemo);
}
