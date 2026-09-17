import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:binnacle_connect/main.dart';
import 'package:binnacle_connect/core/app_config.dart';
import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/models/credential.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';
import 'package:binnacle_connect/ui/widgets/simulated_wake_view.dart';

void main() {
  testWidgets('Live mode contains no demo media or simulated video', (tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pump(const Duration(milliseconds: 500));
    final context = tester.element(find.text('My Boat').first);
    final clips = context.read<ClipRepository>();
    expect(clips.clips, isEmpty);
    expect(find.byType(SimulatedWakeView), findsNothing);
    expect(find.textContaining('Core health unavailable'), findsWidgets);
    expect(() => clips.seedDemo(), throwsStateError);
    expect(() => clips.addFromCapture(kind: ClipKind.photo, preset: 'test'), throwsStateError);
    expect(() => clips.importFallClip(), throwsStateError);
    await expectLater(context.read<PairingService>().debugSimulatePairing(
        unclaimed: false, role: DeviceRole.owner), throwsStateError);
    await tester.tap(find.text('Live').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Live video unavailable'), findsOneWidget);
    expect(find.text('Telemetry unavailable'), findsOneWidget);

    // BIN-9: a Core build must never expose a control that fabricates a
    // man-overboard alert locally — MobAlertState.trigger() bypasses the
    // Core entirely, so this demo-only affordance must not render here.
    expect(find.text('Simulate fall alert (demo)'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: AppConfig.isDemo);

  testWidgets('Core mode never exposes the debug pairing-simulation affordance', (tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pump(const Duration(milliseconds: 500));

    // Unpaired on a fresh Core-mode launch, so My Boat's "Pair a device"
    // entry point is present — follow it into the real PairingScreen.
    await tester.tap(find.text('Pair a device'));
    await tester.pumpAndSettle();

    // BIN-6: debugSimulatePairing() fabricates a credential and throws
    // StateError outside demo mode — this button must not render at all in
    // a Core build, not merely fail safely if tapped.
    expect(find.text('Simulate pairing to an unclaimed unit'), findsNothing);
    expect(find.textContaining('DEMO ONLY'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: AppConfig.isDemo);
}
