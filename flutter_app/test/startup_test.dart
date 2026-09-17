import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:binnacle_connect/ui/widgets/connect_startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Decode real bundled images outside the widget fake clock. The timer tests
// below still use pump durations exclusively, never wall-clock sleeps.
Future<void> loadBranding(WidgetTester tester) async {
  final context = tester.element(find.byType(ConnectStartup));
  await tester.runAsync(() async {
    await Future.wait([
      precacheImage(const AssetImage(ConnectStartup.backgroundAsset), context),
      precacheImage(const AssetImage(ConnectStartup.logoAsset), context),
    ]);
  });
  await tester.pump();
  await tester.runAsync(() async {
    await precacheImage(const AssetImage(ConnectStartup.logoAsset), context);
  });
  await tester.pump();
}

Future<void> warmBranding(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  final context = tester.element(find.byType(SizedBox).first);
  await tester.runAsync(() async {
    await Future.wait([
      precacheImage(const AssetImage(ConnectStartup.backgroundAsset), context),
      precacheImage(const AssetImage(ConnectStartup.logoAsset), context),
    ]);
  });
}

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('SPLASH_EVIDENCE')) {
      final font = File(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/roboto-regular.ttf');
      final loader = FontLoader('sans-serif')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
    }
  });
  Widget app(Future<void> Function() initialize, {Widget? child}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ConnectStartup(
            initialize: initialize,
            child: child ?? const Scaffold(body: Text('Real destination'))),
      );

  testWidgets('real branding renders; fast startup waits the full minimum',
      (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(app(() => ready.future));
    await loadBranding(tester);
    expect(find.text('CONNECT'), findsOneWidget);
    expect(find.image(const AssetImage(ConnectStartup.logoAsset)),
        findsNWidgets(2));
    ready.complete();
    await tester.pump(const Duration(milliseconds: 3499));
    expect(find.text('CONNECT'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(ConnectStartup.transitionDuration);
    expect(find.text('CONNECT'), findsNothing);
    expect(find.text('Real destination'), findsOneWidget);
  });

  testWidgets('slow readiness remains gated beyond five seconds',
      (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(app(() => ready.future));
    await loadBranding(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('CONNECT'), findsOneWidget);
    ready.complete();
    await tester.pump();
    await tester.pump(ConnectStartup.transitionDuration);
    expect(find.text('CONNECT'), findsNothing);
  });

  testWidgets('failed restoration stays closed and can retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(app(() async {
      if (++attempts == 1) throw StateError('private storage detail');
    }));
    await loadBranding(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('private storage detail'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(ConnectStartup.transitionDuration);
    expect(attempts, 2);
    expect(find.text('CONNECT'), findsNothing);
  });

  testWidgets('underlying destination cannot be tapped during splash',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(() async {},
        child: Center(
            child: TextButton(
                onPressed: () => taps++,
                child: const Text('Destination action')))));
    await loadBranding(tester);
    await tester.tap(find.text('Destination action'), warnIfMissed: false);
    expect(taps, 0);
    await tester.pump(ConnectStartup.minimumDuration);
    await tester.pump(ConnectStartup.transitionDuration);
    await tester.tap(find.text('Destination action'));
    expect(taps, 1);
  });

  testWidgets('disposal during startup cancels timers and late completion',
      (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(app(() => ready.future));
    await loadBranding(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    ready.complete();
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion preserves the minimum and skips motion',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(app(() async {}));
    await loadBranding(tester);
    expect(
        tester
            .widget<ScaleTransition>(find.byType(ScaleTransition).last)
            .scale
            .value,
        1);
    await tester.pump(const Duration(milliseconds: 3499));
    expect(find.text('CONNECT'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('CONNECT'), findsNothing);
  });

  testWidgets('route changes during startup survive the transition',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final ready = Completer<void>();
    var starts = 0;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) => ConnectStartup(
          initialize: () {
            starts++;
            return ready.future;
          },
          child: child!),
      home: const Scaffold(body: Text('Home route')),
    ));
    await loadBranding(tester);
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Incoming destination'))));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('CONNECT'), findsOneWidget);
    ready.complete();
    await tester.pump();
    await tester.pump(ConnectStartup.transitionDuration);
    expect(find.text('CONNECT'), findsNothing);
    expect(find.text('Incoming destination'), findsOneWidget);
    expect(starts, 1);
  });

  for (final size in [
    const Size(412, 915),
    const Size(360, 640),
    const Size(915, 412)
  ]) {
    testWidgets('actual splash render ${size.width}x${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: key, child: app(() => Completer<void>().future)));
      await loadBranding(tester);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('SPLASH_EVIDENCE')) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
              '../docs/evidence/splash_${size.width.toInt()}x${size.height.toInt()}.png');
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
