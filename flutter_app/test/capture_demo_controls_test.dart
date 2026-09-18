// The Live screen in Recorded Demo Mode: zoom, Snapshot and Save Highlight
// work locally, vessel/Core controls stay disabled, and NO Core command is
// ever sent by the local media actions.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/services/camera_media_source.dart';
import 'package:binnacle_connect/core/services/control_channel_service.dart';
import 'package:binnacle_connect/core/services/demo_media.dart';
import 'package:binnacle_connect/core/services/mob_alert_state.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';
import 'package:binnacle_connect/core/services/telemetry_socket.dart';
import 'package:binnacle_connect/ui/screens/capture_screen.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';
import 'package:binnacle_connect/ui/theme/binnacle_theme.dart';

import 'support/screen_size.dart';
import 'support/fake_demo_media.dart';

class _Harness {
  final RecordingControlChannelService control =
      RecordingControlChannelService();
  final FakeFrameExtractor extractor = FakeFrameExtractor();
  final ClipRepository library = ClipRepository();
  final Directory dir =
      Directory.systemTemp.createTempSync('capture_demo_test_');
  late final DemoRecordedCameraSource source;
  late final DemoMediaCapture capture;

  _Harness({Duration? position, bool playerReady = true}) {
    capture =
        DemoMediaCapture(extractor: extractor, mediaDirectory: () async => dir);
    source = DemoRecordedCameraSource();
    if (playerReady) {
      source.attachPlayer(
        readPosition: () async => position ?? const Duration(seconds: 47),
        duration: const Duration(seconds: 130),
      );
    }
  }

  Widget build() => MultiProvider(
        providers: [
          ChangeNotifierProvider<ControlChannelService>.value(value: control),
          ChangeNotifierProvider(create: (_) => TelemetrySocket()),
          ChangeNotifierProvider(create: (_) => MobAlertState()),
          ChangeNotifierProvider(create: (_) => PairingService()),
          ChangeNotifierProvider<ClipRepository>.value(value: library),
          Provider<DemoMediaCapture>.value(value: capture),
        ],
        child: MaterialApp(
          theme: BinnacleTheme.dark(),
          home: CaptureScreen(mediaSourceForTesting: source),
        ),
      );

  void dispose() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _pumpScreen(WidgetTester tester, _Harness h) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  await tester.pumpWidget(h.build());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {});

  testWidgets(
      'media controls are enabled, vessel controls stay disabled, no Core command is sent',
      (tester) async {
    usePortraitPhone(tester);
    final h = _Harness();
    addTearDown(h.dispose);
    await _pumpScreen(tester, h);

    expect(find.text('DEMO — RECORDED CAMERA FEED'), findsOneWidget);

    // Vessel / Core controls: presets, manual/AI orientation, arm switch.
    await tester.tap(find.text('Wakeboard'), warnIfMissed: false);
    await tester.tap(find.byIcon(Icons.crop_rotate_outlined),
        warnIfMissed: false);
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);

    // Local media controls: zoom.
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('1.5×'), findsOneWidget);

    // Revised notice replaces the old "controls are disabled" copy.
    await tester.scrollUntilVisible(
      find.textContaining(
          'Snapshot, Highlight, and digital Zoom are simulated locally'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
        find.textContaining('Vessel controls remain disabled'), findsOneWidget);
    expect(
        find.textContaining(
            'camera, framing, capture, and vessel controls are disabled'),
        findsNothing);

    expect(h.control.commands, isEmpty,
        reason: 'nothing here may reach a Core');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'zoom + and - change the local zoom in 0.5x steps and clamp at 1.0x and 4.0x',
      (tester) async {
    usePortraitPhone(tester);
    final h = _Harness();
    addTearDown(h.dispose);
    await _pumpScreen(tester, h);

    expect(find.text('1.0×'), findsOneWidget);
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('1.5×'), findsOneWidget);
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('2.0×'), findsOneWidget);
    expect(h.source.zoom.value, 2.0);

    await tester.tap(find.text('−'));
    await tester.tap(find.text('−'));
    await tester.pump();
    expect(find.text('1.0×'), findsOneWidget);
    // Already at the minimum: another tap changes nothing.
    await tester.tap(find.text('−'), warnIfMissed: false);
    await tester.pump();
    expect(h.source.zoom.value, 1.0);

    for (var i = 0; i < 8; i++) {
      await tester.tap(find.text('+'), warnIfMissed: false);
      await tester.pump();
    }
    expect(find.text('4.0×'), findsOneWidget);
    expect(h.source.zoom.value, 4.0);

    expect(h.control.commands, isEmpty,
        reason: 'demo zoom must never send nudge_zoom');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'Snapshot saves a real image of the playback position to the Library',
      (tester) async {
    usePortraitPhone(tester);
    final h = _Harness(position: const Duration(seconds: 47));
    addTearDown(h.dispose);
    await _pumpScreen(tester, h);

    await tester.tap(find.byIcon(Icons.camera_alt_outlined));
    await _settle(tester);

    expect(find.text('Snapshot saved to Library and Photos'), findsOneWidget);
    expect(find.text('Demo capture saved'), findsNothing);
    final photo = h.library.clips
        .firstWhere((c) => c.kind == ClipKind.photo && c.isDemoOrigin);
    expect(photo.origin, ClipOrigin.demoLocalCapture);
    expect(File(photo.localPath!).existsSync(), isTrue);
    expect(h.extractor.requests.single.position, const Duration(seconds: 47));
    expect(h.control.commands, isEmpty, reason: 'no snapshot command in Demo');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'Save Highlight uses the playhead and the configured pre/post roll',
      (tester) async {
    usePortraitPhone(tester);
    final h = _Harness(position: const Duration(seconds: 47));
    addTearDown(h.dispose);
    await _pumpScreen(tester, h);

    await tester.tap(find.text('SAVE\nHIGHLIGHT'));
    await _settle(tester);

    expect(find.text('Highlight saved to Library'), findsOneWidget);
    final clip = h.library.clips.firstWhere((c) => c.id.startsWith('demo-hl-'));
    // Demo capture state is 15 s pre-roll and 30 s post-roll.
    expect(clip.segment!.start, const Duration(seconds: 32));
    expect(clip.segment!.end, const Duration(seconds: 77));
    expect(clip.duration, const Duration(seconds: 45));
    expect(clip.origin, ClipOrigin.demoSegment);
    expect(h.control.commands, isEmpty,
        reason: 'no save_highlight command in Demo');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a highlight near the end of the source clamps to it',
      (tester) async {
    usePortraitPhone(tester);
    final h = _Harness(position: const Duration(seconds: 128));
    addTearDown(h.dispose);
    await _pumpScreen(tester, h);

    await tester.tap(find.text('SAVE\nHIGHLIGHT'));
    await _settle(tester);

    final clip = h.library.clips.firstWhere((c) => c.id.startsWith('demo-hl-'));
    expect(clip.segment!.end, const Duration(seconds: 130));
    expect(clip.segment!.start, const Duration(seconds: 113));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a failed snapshot shows the error and saves nothing',
      (tester) async {
    usePortraitPhone(tester);
    final h = _Harness();
    addTearDown(h.dispose);
    h.extractor.failWith = FrameExtractionException('decoder unavailable');
    await _pumpScreen(tester, h);

    await tester.tap(find.byIcon(Icons.camera_alt_outlined));
    await _settle(tester);

    expect(find.text('Snapshot failed: decoder unavailable'), findsOneWidget);
    expect(find.textContaining('saved to Library'), findsNothing);
    expect(h.library.clips.where((c) => c.kind == ClipKind.photo), isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'capture before the recorded feed is ready fails visibly, not silently',
      (tester) async {
    usePortraitPhone(tester);
    final h = _Harness(playerReady: false);
    addTearDown(h.dispose);
    await _pumpScreen(tester, h);

    await tester.tap(find.text('SAVE\nHIGHLIGHT'));
    await _settle(tester);

    expect(find.textContaining('Highlight failed'), findsOneWidget);
    expect(find.text('Highlight saved to Library'), findsNothing);
    expect(h.library.clips.where((c) => c.id.startsWith('demo-hl-')), isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });
}
