import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:binnacle_connect/ui/widgets/connect_startup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Precaches real, bundled artwork on the already-mounted ConnectStartup.
Future<void> loadBranding(WidgetTester tester) async {
  final context = tester.element(find.byType(ConnectStartup));
  await tester.runAsync(() => Future.wait([
        precacheImage(const AssetImage(ConnectStartup.backgroundAsset), context),
        precacheImage(const AssetImage(ConnectStartup.logoAsset), context),
      ]));
  await tester.pump();
  // A second, tiny pump "primes" the entrance AnimationController's ticker:
  // it was started via forward() inside a postFrameCallback in the pump()
  // above, and a Ticker's very first invocation sets its own start time on
  // that first callback rather than when forward() was called — so a
  // single large-duration pump() immediately after would see elapsed=0 for
  // that whole jump (frozen at the animation's start value) instead of
  // real progress. This only matters for tests that check the animation's
  // actual value/opacity (e.g. the render-evidence tests below); the
  // gating/timing tests don't care and would pass either way.
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  setUpAll(() async {
    // Evidence-only: widget tests render all text with the placeholder
    // "Ahem" test font by default, so CONNECT would show as blank boxes in
    // the captured screenshots below even though a real device renders the
    // 'monospace' family correctly (already confirmed on a physical S25
    // Ultra — see docs/evidence). Loading a real bundled font under that
    // family name here only affects this file's own evidence captures.
    if (const bool.fromEnvironment('SPLASH_EVIDENCE')) {
      final font = File(
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/roboto-medium.ttf');
      final loader = FontLoader('monospace')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
    }
  });

  Widget app(Future<void> Function() initialize, {Widget? child}) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ConnectStartup(
            initialize: initialize,
            child: child ?? const Scaffold(body: Text('Real destination'))),
      );

  testWidgets('fast successful init still waits the full minimum (early-exit prevention)',
      (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(app(() => ready.future));
    await loadBranding(tester);
    expect(find.text('CONNECT'), findsOneWidget);
    // Init completes almost immediately...
    ready.complete();
    await tester.pump();
    // ...but the splash must still be up right up to the 3.5s floor.
    await tester.pump(const Duration(milliseconds: 3498));
    expect(find.text('CONNECT'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(ConnectStartup.transitionDuration);
    expect(find.text('CONNECT'), findsNothing);
    expect(find.text('Real destination'), findsOneWidget);
  });

  testWidgets('slow readiness stays gated well past the minimum', (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(app(() => ready.future));
    await loadBranding(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('CONNECT'), findsOneWidget);
    ready.complete();
    await tester.pump();
    await tester.pump(ConnectStartup.transitionDuration);
    expect(find.text('CONNECT'), findsNothing);
    expect(find.text('Real destination'), findsOneWidget);
  });

  testWidgets('failed initialize shows a visible retry, not a swallowed error',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(app(() async {
      if (++attempts == 1) throw StateError('credential store detail');
    }));
    await loadBranding(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('RETRY'), findsOneWidget);
    expect(find.textContaining('credential store detail'), findsNothing);

    await tester.tap(find.text('RETRY'));
    await tester.pump();
    await tester.pump(ConnectStartup.transitionDuration);
    expect(attempts, 2);
    expect(find.text('RETRY'), findsNothing);
    expect(find.text('Real destination'), findsOneWidget);
  });

  testWidgets('the real app cannot be interacted with while the splash is up',
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

  testWidgets('disposal during startup cancels timers and ignores late completion',
      (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(app(() => ready.future));
    await loadBranding(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    ready.complete();
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('logo scale never leaves [0.94, 1.0] during the entrance (scale clamp)',
      (tester) async {
    await tester.pumpWidget(app(() => Completer<void>().future));
    await loadBranding(tester);
    final scaleFinder = find.byKey(const ValueKey('connect-startup-logo-scale'));

    // Sample the scale across the whole entrance in small steps — this
    // must hold at every intermediate frame, not just start/end, since an
    // overshooting curve could briefly exceed 1.0 without either endpoint
    // ever showing it.
    for (var elapsedMs = 0; elapsedMs <= 1400; elapsedMs += 50) {
      final scale = tester.widget<ScaleTransition>(scaleFinder).scale.value;
      expect(scale, greaterThanOrEqualTo(0.94),
          reason: 'at t=${elapsedMs}ms');
      expect(scale, lessThanOrEqualTo(1.0), reason: 'at t=${elapsedMs}ms');
      await tester.pump(const Duration(milliseconds: 50));
    }
    // And it must actually have reached full scale by rest, not stalled
    // short of it.
    expect(tester.widget<ScaleTransition>(scaleFinder).scale.value, 1.0);
  });

  testWidgets('reduced motion preserves the minimum floor but skips the animation',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(app(() async {}));
    await loadBranding(tester);
    expect(
        tester
            .widget<ScaleTransition>(find.byKey(const ValueKey('connect-startup-logo-scale')))
            .scale
            .value,
        1);
    await tester.pump(const Duration(milliseconds: 3498));
    expect(find.text('CONNECT'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('CONNECT'), findsNothing);
  });

  testWidgets('a route pushed during startup survives the transition (route preservation)',
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
    // Still gated — the pushed route hasn't been reachable yet, but it must
    // not have been dropped or caused initialize() to restart.
    expect(find.text('CONNECT'), findsOneWidget);
    expect(starts, 1);
    ready.complete();
    await tester.pump();
    await tester.pump(ConnectStartup.transitionDuration);
    expect(find.text('CONNECT'), findsNothing);
    // "Incoming destination" is the topmost, visible route. "Home route"
    // legitimately still exists underneath — Navigator keeps a prior route
    // mounted (offstage) beneath the current one by default; that's not a
    // splash-preservation bug, it's ordinary Navigator behavior.
    expect(find.text('Incoming destination'), findsOneWidget);
    expect(starts, 1);
  });

  for (final size in [
    const Size(412, 917), // tall-phone/S25-Ultra-like logical portrait
    const Size(360, 640), // compact phone portrait
    const Size(915, 412), // landscape
  ]) {
    testWidgets(
        'renders without overflow or clipping at ${size.width.toInt()}x${size.height.toInt()} (responsive layout)',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
          RepaintBoundary(key: key, child: app(() => Completer<void>().future)));
      await loadBranding(tester);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.takeException(), isNull);

      // Landscape lays the logo/wordmark out side-by-side (Row); portrait
      // stacks them (Column) — verify the actual layout swapped, not just
      // that nothing overflowed.
      final isLandscape = size.width > size.height;
      final flex = tester.widget<Flex>(find.byType(Flex));
      expect(flex.direction,
          isLandscape ? Axis.horizontal : Axis.vertical);

      if (const bool.fromEnvironment('SPLASH_EVIDENCE')) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file =
              File('../docs/evidence/splash_${size.width.toInt()}x${size.height.toInt()}.png');
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
