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
import 'package:binnacle_connect/ui/widgets/simulated_wake_view.dart';

void main() {
  testWidgets('Live mode contains no demo media or simulated video', (tester) async {
    // main.dart's _AppStartup now genuinely awaits PairingService.restore()
    // (a real Keychain/Keystore read) as part of the splash readiness gate,
    // not just a fire-and-forget call — so, same as widget_test.dart, the
    // platform channel needs a mock or the read never resolves under the
    // test binding's fake-async pump and the splash never clears.
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pump(const Duration(milliseconds: 3600));
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
    await tester.pump(const Duration(milliseconds: 3600));
    expect(find.textContaining('Live video unavailable'), findsOneWidget);
    expect(find.text('Telemetry unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: AppConfig.isDemo);
}
