import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:binnacle_connect/main.dart';
import 'package:binnacle_connect/core/app_config.dart';
import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/models/credential.dart';
import 'package:binnacle_connect/core/models/vessel_state.dart';
import 'package:binnacle_connect/core/services/mob_alert_state.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';
import 'package:binnacle_connect/ui/screens/capture_screen.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';
import 'package:binnacle_connect/ui/widgets/simulated_wake_view.dart';

/// ListView(children:) only mounts Elements for children near the
/// viewport, so an off-screen "findsNothing" would pass even if the demo
/// button were still there, ungated — this scrolls Capture's own
/// Scrollable (not some other still-mounted tab's) until [finder] resolves
/// or the scroll gives up, so a real absence can actually be asserted.
Future<void> _scrollCaptureUntilVisible(WidgetTester tester, Finder finder) async {
  final scrollable =
      find.descendant(of: find.byType(CaptureScreen), matching: find.byType(Scrollable)).evaluate().first;
  final scrollableFinder = find.byElementPredicate((e) => e == scrollable);
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(scrollableFinder, const Offset(0, -300));
    await tester.pump();
  }
}

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
    // man-overboard alert locally — scroll all the way down (past Safety)
    // to prove it is genuinely absent, not just off-screen.
    final safetyReadiness = find.text('UNKNOWN');
    await _scrollCaptureUntilVisible(tester, safetyReadiness);
    expect(safetyReadiness, findsWidgets); // fall-detection + MOB-alert readiness, unknown before any state
    expect(find.textContaining('Simulate fall alert'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: AppConfig.isDemo);

  test('Core mode: MobAlertState mirrors a Core-reported event, never the demo fixed coordinates', () {
    final mob = MobAlertState();
    mob.applyCoreEvent(const MobEvent(active: true, lat: '10.5 N', lon: '20.25 W', headingDegrees: 270));
    expect(mob.active, isTrue);
    expect(mob.lat, '10.5 N');
    expect(mob.lon, '20.25 W');
    expect(mob.headingDegrees, 270.0);
    expect(mob.simulated, isFalse);
    expect(mob.lat, isNot('36.02083° N'), reason: 'must never be the demo-only fixed coordinate');

    // Core is the only authority: absence of a mob object means Core is
    // reporting no active event right now, and this must clear the display
    // even if a previous event was active.
    mob.applyCoreEvent(MobEvent.fromJson(null));
    expect(mob.active, isFalse);
  }, skip: AppConfig.isDemo);

  test('Core mode: demo MOB simulation is unreachable', () {
    final mob = MobAlertState();
    expect(() => mob.triggerDemo(), throwsStateError);
    expect(mob.active, isFalse);
  }, skip: AppConfig.isDemo);
}
