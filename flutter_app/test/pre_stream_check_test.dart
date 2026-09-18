// Pre-stream check: blocking vs advisory separation, and that "Start
// broadcast" stays disabled while a blocking failure exists.

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:binnacle_connect/core/models/live_broadcast.dart';
import 'package:binnacle_connect/core/services/connected_services.dart';
import 'package:binnacle_connect/ui/screens/pre_stream_check_screen.dart';
import 'package:binnacle_connect/ui/theme/binnacle_theme.dart';

import 'support/fake_media_services.dart';

Widget _harness({
  required ConnectedServicesService connected,
  required List<BroadcastDestination> destinations,
  required VoidCallback onStart,
}) {
  return MultiProvider(
    providers: [ChangeNotifierProvider<ConnectedServicesService>.value(value: connected)],
    child: MaterialApp(
      theme: BinnacleTheme.dark(),
      home: PreStreamCheckScreen(
        view: OutgoingView.rawCamera,
        destinations: destinations,
        onStartBroadcast: onStart,
      ),
    ),
  );
}

void main() {
  setUp(() {
    ConnectivityPlatform.instance = FakeConnectivityPlatform();
  });

  testWidgets('a destination with no linked account blocks Start broadcast', (tester) async {
    var started = false;
    await tester.pumpWidget(_harness(
      connected: LocalConnectedServicesService(), // YouTube reports not connected
      destinations: const [BroadcastDestination(kind: DestinationKind.youtube)],
      onStart: () => started = true,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not connected'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start broadcast'));
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Start broadcast'), warnIfMissed: false);
    expect(started, isFalse);
  });

  testWidgets('Binnacle Live (no account needed) never blocks, and Start broadcast is enabled',
      (tester) async {
    var started = false;
    await tester.pumpWidget(_harness(
      connected: LocalConnectedServicesService(),
      destinations: const [BroadcastDestination(kind: DestinationKind.binnacleLive)],
      onStart: () => started = true,
    ));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start broadcast'));
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('Start broadcast'));
    expect(started, isTrue);
  });

  testWidgets('camera/source and audio show as advisory, never claimed as verified', (tester) async {
    await tester.pumpWidget(_harness(
      connected: LocalConnectedServicesService(),
      destinations: const [BroadcastDestination(kind: DestinationKind.binnacleLive)],
      onStart: () {},
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('isn\'t reported by Core'), findsOneWidget);
    expect(find.textContaining('Captured on Vision hardware'), findsOneWidget);
    expect(
        find.textContaining('does not guarantee an uninterrupted stream'),
        findsOneWidget);
  });
}
