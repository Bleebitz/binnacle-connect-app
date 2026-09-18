// Landscape Live camera console: orientation, control visibility, Clean View,
// zoom (pinch / +- / presets / double-tap), Snapshot, Highlight, the Demo
// timeline, Rider Lock, view modes, and the Demo/Core separation.

import 'dart:io';

import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/services/camera_media_source.dart';
import 'package:binnacle_connect/core/services/control_channel_service.dart';
import 'package:binnacle_connect/core/services/demo_media.dart';
import 'package:binnacle_connect/core/services/mob_alert_state.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';
import 'package:binnacle_connect/core/services/telemetry_socket.dart';
import 'package:binnacle_connect/core/services/webrtc_service.dart';
import 'package:binnacle_connect/main.dart';
import 'package:binnacle_connect/ui/widgets/connect_startup.dart';
import 'package:binnacle_connect/ui/screens/capture_screen.dart';
import 'package:binnacle_connect/ui/screens/landscape_console_controller.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';
import 'package:binnacle_connect/ui/theme/binnacle_theme.dart';
import 'package:binnacle_connect/ui/widgets/eptz_video_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_demo_media.dart';

const _land = Size(960, 480);
const _port = Size(480, 960);

class _Harness {
  final RecordingControlChannelService control =
      RecordingControlChannelService();
  final FakeFrameExtractor extractor = FakeFrameExtractor();
  final ClipRepository library = ClipRepository();
  final Directory dir = Directory.systemTemp.createTempSync('landscape_test_');
  late final CameraMediaSource source;
  late final DemoMediaCapture capture;
  final List<String> opened = [];
  int exits = 0;
  Duration position;
  final List<Duration> seeks = [];

  _Harness({this.position = const Duration(seconds: 47), bool live = false}) {
    capture =
        DemoMediaCapture(extractor: extractor, mediaDirectory: () async => dir);
    if (live) {
      source = LiveWebRtcCameraSource(
          webRtc: WebRtcService(renderer: SimulatedVideoRenderer()));
    } else {
      final demo = DemoRecordedCameraSource();
      demo.attachPlayer(
        readPosition: () async => position,
        duration: const Duration(seconds: 130),
        seekTo: (t) async {
          seeks.add(t);
          position = t;
        },
      );
      source = demo;
    }
  }

  DemoRecordedCameraSource get demo => source as DemoRecordedCameraSource;

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
          home: CaptureScreen(
            mediaSourceForTesting: source,
            onExitConsole: () => exits++,
            onOpenClip: opened.add,
          ),
        ),
      );

  void dispose() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

Future<void> _size(WidgetTester tester, Size s) async {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _start(WidgetTester tester, _Harness h,
    {Size size = _land}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(h.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(h.build());
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Finder _k(String key) => find.byKey(ValueKey(key));

double _opacity(WidgetTester tester, String key) =>
    tester.widget<AnimatedOpacity>(_k(key)).opacity;

Future<void> _idle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3, milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('orientation', () {
    testWidgets(
        'portrait keeps the normal Live layout, landscape shows the console',
        (tester) async {
      final h = _Harness();
      await _start(tester, h, size: _port);
      expect(_k('console-min-hud'), findsNothing);
      expect(find.text('Wakesurf'), findsOneWidget, reason: 'preset row');

      await _size(tester, _land);
      expect(_k('console-min-hud'), findsOneWidget);
      expect(find.text('Wakesurf'), findsNothing);

      await _size(tester, _port);
      expect(_k('console-min-hud'), findsNothing);
      expect(find.text('Wakesurf'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'repeated rotation keeps the same video element, zoom, lock and view mode',
        (tester) async {
      final h = _Harness();
      await _start(tester, h, size: _port);
      h.demo.zoom.setZoom(2.5);
      h.demo.riderLock.select('other');
      h.demo.viewMode.value = DemoViewMode.raw;
      final first = tester.element(find.byType(EptzVideoView));

      for (var i = 0; i < 3; i++) {
        await _size(tester, _land);
        await _size(tester, _port);
      }
      await _size(tester, _land);

      expect(
          identical(tester.element(find.byType(EptzVideoView)), first), isTrue,
          reason: 'the video (and its player) must be moved, not rebuilt');
      expect(find.byType(EptzVideoView), findsOneWidget);
      expect(h.demo.zoom.value, 2.5);
      expect(h.demo.riderLock.value, 'other');
      expect(h.demo.viewMode.value, DemoViewMode.raw);
      expect(h.seeks, isEmpty, reason: 'rotation must not seek the video');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('an inactive Live tab does not show the console',
        (tester) async {
      final h = _Harness();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(h.dispose);
      tester.view.physicalSize = _land;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ControlChannelService>.value(value: h.control),
          ChangeNotifierProvider(create: (_) => TelemetrySocket()),
          ChangeNotifierProvider(create: (_) => MobAlertState()),
          ChangeNotifierProvider(create: (_) => PairingService()),
          ChangeNotifierProvider<ClipRepository>.value(value: h.library),
          Provider<DemoMediaCapture>.value(value: h.capture),
        ],
        child: MaterialApp(
          theme: BinnacleTheme.dark(),
          home: CaptureScreen(
              mediaSourceForTesting: h.source, isActiveTab: false),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_k('console-min-hud'), findsNothing);
    });

    testWidgets(
        'the app shell hides bottom navigation only for landscape Live and restores it in portrait',
        (tester) async {
      ConnectStartup.debugSkipForTesting = true;
      addTearDown(() => ConnectStartup.debugSkipForTesting = false);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = _land;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const BinnacleConnectApp());
      await tester.pump();
      expect(find.byType(NavigationBar), findsOneWidget,
          reason: 'My Boat in landscape keeps normal navigation');

      await tester.tap(find.text('Live').last);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(NavigationBar), findsNothing);
      expect(_k('console-min-hud'), findsOneWidget);

      await _size(tester, _port);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(_k('console-min-hud'), findsNothing);

      await _size(tester, _land);
      await tester.pump(const Duration(milliseconds: 500));
      // The exit control returns to My Boat, where navigation is back.
      await tester.tap(_k('console-exit'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the exit control leaves the console', (tester) async {
      final h = _Harness();
      await _start(tester, h);
      await tester.tap(_k('console-exit'));
      expect(h.exits, 1);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('control visibility', () {
    testWidgets(
        'controls start visible, fade after ~3 s, the minimum HUD stays, a tap restores',
        (tester) async {
      final h = _Harness();
      await _start(tester, h);
      expect(_opacity(tester, 'console-controls-right'), 1);
      expect(_opacity(tester, 'console-controls-left'), 1);

      await _idle(tester);
      expect(_opacity(tester, 'console-controls-right'), 0);
      expect(_opacity(tester, 'console-controls-left'), 0);
      // Persistent minimum HUD: Demo label, Track, lock, rec, link, zoom.
      expect(find.text('DEMO — RECORDED CAMERA FEED'), findsOneWidget);
      expect(_k('console-zoom-chip'), findsOneWidget);
      expect(find.text('LOCK · SIM'), findsOneWidget);
      expect(find.text('PLAYBACK · NOT REC'), findsOneWidget);
      expect(find.text('LINK SIMULATED'), findsOneWidget);
      expect(find.textContaining('TRACK'), findsWidgets);
      // Hidden controls are not tappable.
      final ignore = tester.widget<IgnorePointer>(find
          .ancestor(
              of: _k('console-controls-right'),
              matching: find.byType(IgnorePointer))
          .first);
      expect(ignore.ignoring, isTrue);

      await tester.tapAt(const Offset(480, 240));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_opacity(tester, 'console-controls-right'), 1);
      expect(_opacity(tester, 'console-controls-left'), 1);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('any control use restarts the idle clock', (tester) async {
      final h = _Harness();
      await _start(tester, h);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(_k('console-zoom-in'));
      await tester.pump(const Duration(seconds: 2));
      expect(_opacity(tester, 'console-controls-right'), 1,
          reason: '2 s after the tap, well inside the 3 s window');
      await _idle(tester);
      expect(_opacity(tester, 'console-controls-right'), 0);
    });

    testWidgets(
        'Clean View (button and swipe) hides controls but keeps Demo label and Track; tap restores',
        (tester) async {
      final h = _Harness();
      await _start(tester, h);

      await tester.tap(_k('console-clean-view'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_opacity(tester, 'console-controls-right'), 0);
      expect(find.text('DEMO — RECORDED CAMERA FEED'), findsOneWidget);
      expect(find.textContaining('TRACK'), findsWidgets);
      expect(find.text('PLAYBACK · NOT REC'), findsOneWidget);
      expect(_k('console-zoom-chip'), findsNothing,
          reason: 'Clean View drops the zoom and link chips');
      expect(find.text('LINK SIMULATED'), findsNothing);

      await tester.tapAt(const Offset(480, 240));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_opacity(tester, 'console-controls-right'), 1);

      // Swipe down inside the video area.
      await tester.dragFrom(const Offset(480, 150), const Offset(0, 160));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_opacity(tester, 'console-controls-right'), 0);
      expect(find.text('DEMO — RECORDED CAMERA FEED'), findsOneWidget);
      await tester.tapAt(const Offset(480, 240));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_opacity(tester, 'console-controls-right'), 1);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'a swipe that starts in the top system strip, or a sideways drag, does not enter Clean View',
        (tester) async {
      final h = _Harness();
      await _start(tester, h);
      await tester.dragFrom(const Offset(480, 6), const Offset(0, 160));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_opacity(tester, 'console-controls-right'), 1);

      await tester.dragFrom(const Offset(300, 200), const Offset(200, 90));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_opacity(tester, 'console-controls-right'), 1);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('zoom (Recorded Demo is local)', () {
    testWidgets('+ / - step 0.5x and clamp at 1.0x and 4.0x; no Core command',
        (tester) async {
      final h = _Harness();
      await _start(tester, h);
      await tester.tap(_k('console-zoom-in'));
      await tester.pump();
      expect(h.demo.zoom.value, 1.5);
      for (var i = 0; i < 10; i++) {
        await tester.tap(_k('console-zoom-in'), warnIfMissed: false);
      }
      await tester.pump();
      expect(h.demo.zoom.value, DemoZoom.max);
      for (var i = 0; i < 12; i++) {
        await tester.tap(_k('console-zoom-out'), warnIfMissed: false);
      }
      await tester.pump();
      expect(h.demo.zoom.value, DemoZoom.min);
      expect(h.control.commands, isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('presets set 1x 2x 3x 4x and the chip shows the real zoom',
        (tester) async {
      final h = _Harness();
      await _start(tester, h);
      for (final z in [2, 3, 4, 1]) {
        await tester.tap(_k('console-preset-$z'));
        await tester.pump();
        expect(h.demo.zoom.value, z.toDouble());
        expect(find.text('$z.0×'), findsOneWidget);
      }
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('pinch zooms and clamps; a one-finger drag does not',
        (tester) async {
      final h = _Harness();
      await _start(tester, h);
      final c = const Offset(480, 240);
      final a = await tester.startGesture(c - const Offset(30, 0), pointer: 1);
      final b = await tester.startGesture(c + const Offset(30, 0), pointer: 2);
      await a.moveTo(c - const Offset(75, 0));
      await b.moveTo(c + const Offset(75, 0));
      await tester.pump();
      expect(h.demo.zoom.value, greaterThan(1.3),
          reason: "fingers spread from 60 to 150 apart");
      await a.moveTo(c - const Offset(400, 0));
      await b.moveTo(c + const Offset(400, 0));
      await tester.pump();
      expect(h.demo.zoom.value, DemoZoom.max);
      await a.up();
      await b.up();
      expect(h.control.commands, isEmpty);
      // Pinching must not have entered Clean View.
      expect(_opacity(tester, 'console-controls-right'), 1);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('double-tap toggles 1x <-> the previous zoom, not a fixed 2x',
        (tester) async {
      final h = _Harness();
      await _start(tester, h);
      h.demo.zoom.setZoom(2.5);
      await tester.pump();

      Future<void> doubleTap() async {
        await tester.tapAt(const Offset(480, 240));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(const Offset(480, 240));
        await tester.pump(const Duration(milliseconds: 400));
      }

      await doubleTap();
      expect(h.demo.zoom.value, 1.0);
      await doubleTap();
      expect(h.demo.zoom.value, 2.5);
      await doubleTap();
      expect(h.demo.zoom.value, 1.0);
      expect(h.control.commands, isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });

    test('DemoZoom remembers the last magnified level, defaulting to 2x', () {
      final z = DemoZoom();
      addTearDown(z.dispose);
      z.toggleReset();
      expect(z.value, 2.0);
      z.setZoom(3.0);
      z.toggleReset();
      expect(z.value, 1.0);
      z.toggleReset();
      expect(z.value, 3.0);
    });
  });

  group('zoom (Core keeps its authoritative path)', () {
    testWidgets('+ and presets send nudge_zoom and apply no local transform',
        (tester) async {
      final h = _Harness(live: true);
      await _start(tester, h);
      await tester.tap(_k('console-zoom-in'));
      await tester.tap(_k('console-preset-3'));
      await tester.pump();
      expect(h.control.commands.where((c) => c == 'nudge_zoom').length, 2);
      expect(_k('console-timeline'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('Snapshot', () {
    testWidgets(
        'saves the real frame at the playback position, shows a thumbnail, opens it in the Library',
        (tester) async {
      final h = _Harness(position: const Duration(seconds: 47));
      await _start(tester, h);
      await tester.tap(_k('console-snapshot'));
      await _settle(tester);

      expect(find.text('Snapshot saved to Library'), findsWidgets);
      final photo = h.library.clips
          .firstWhere((c) => c.kind == ClipKind.photo && c.isDemoOrigin);
      expect(File(photo.localPath!).existsSync(), isTrue);
      expect(h.extractor.requests.single.position, const Duration(seconds: 47));
      expect(_k('console-snapshot-thumbnail'), findsOneWidget);
      expect(h.control.commands, isEmpty);

      await tester.tap(_k('console-snapshot-thumbnail'));
      await tester.pump();
      expect(h.opened, [photo.id]);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_k('console-snapshot-thumbnail'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('the thumbnail disappears on its own', (tester) async {
      final h = _Harness();
      await _start(tester, h);
      await tester.tap(_k('console-snapshot'));
      await _settle(tester);
      expect(_k('console-snapshot-thumbnail'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_k('console-snapshot-thumbnail'), findsNothing);
    });

    testWidgets(
        'a failed snapshot says so: no success message, no thumbnail, no clip',
        (tester) async {
      final h = _Harness();
      h.extractor.failWith = FrameExtractionException('decoder unavailable');
      await _start(tester, h);
      await tester.tap(_k('console-snapshot'));
      await _settle(tester);
      expect(find.text('Snapshot failed: decoder unavailable'), findsWidgets);
      expect(find.text('Snapshot saved to Library'), findsNothing);
      expect(_k('console-snapshot-thumbnail'), findsNothing);
      expect(h.library.clips.where((c) => c.kind == ClipKind.photo), isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('Save Highlight', () {
    testWidgets(
        'uses the playhead with the real pre/post roll and does not touch playback',
        (tester) async {
      final h = _Harness(position: const Duration(seconds: 47));
      await _start(tester, h);
      await tester.tap(_k('console-highlight'));
      await _settle(tester);
      expect(find.text('Highlight saved · 15s before / 30s after'),
          findsOneWidget);
      final clip =
          h.library.clips.firstWhere((c) => c.id.startsWith('demo-hl-'));
      expect(clip.segment!.start, const Duration(seconds: 32));
      expect(clip.segment!.end, const Duration(seconds: 77));
      expect(h.seeks, isEmpty, reason: 'saving must not seek or pause');
      expect(h.control.commands, isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'near the start and near the end the message reports the clamped window',
        (tester) async {
      final start = _Harness(position: const Duration(seconds: 5));
      await _start(tester, start);
      await tester.tap(_k('console-highlight'));
      await _settle(tester);
      expect(
          find.text('Highlight saved · 5s before / 30s after'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('near the end', (tester) async {
      final end = _Harness(position: const Duration(seconds: 125));
      await _start(tester, end);
      await tester.tap(_k('console-highlight'));
      await _settle(tester);
      expect(
          find.text('Highlight saved · 15s before / 5s after'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a highlight before the feed is ready fails visibly',
        (tester) async {
      final h = _Harness();
      h.demo.detachPlayer();
      await _start(tester, h);
      await tester.tap(_k('console-highlight'));
      await _settle(tester);
      expect(find.textContaining('Highlight failed'), findsWidgets);
      expect(find.textContaining('Highlight saved'), findsNothing);
      expect(
          h.library.clips.where((c) => c.id.startsWith('demo-hl-')), isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('Demo timeline', () {
    testWidgets(
        'dragging seeks the player; Track, Snapshot and Highlight then use the new position',
        (tester) async {
      final h = _Harness(position: const Duration(seconds: 10));
      await _start(tester, h);
      expect(_k('console-timeline'), findsOneWidget);

      // Timeline spans the safe area width; a drag ending at ~62% of it.
      final box = tester.getRect(_k('console-timeline'));
      await tester.dragFrom(
          Offset(box.left + 5, box.bottom - 2), Offset(box.width * 0.5, 0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.seeks, isNotEmpty);
      final seeked = h.seeks.last;
      expect(seeked.inSeconds, greaterThan(40));
      expect(h.demo.position.value, seeked);
      // Track state follows the same clock (in the 15..121 s tracking window).
      expect(h.demo.trackState.value.phase, VisionTrackPhase.tracking);

      await tester.tap(_k('console-snapshot'));
      await _settle(tester);
      expect(h.extractor.requests.single.position, seeked);
      await tester.tap(_k('console-highlight'));
      await _settle(tester);
      final clip =
          h.library.clips.firstWhere((c) => c.id.startsWith('demo-hl-'));
      expect(clip.segment!.start, seeked - const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('seeking clamps to the source and a seek before ready throws',
        (tester) async {
      final h = _Harness();
      await h.demo.seekTo(const Duration(seconds: 999));
      expect(h.seeks.last, const Duration(seconds: 130));
      await h.demo.seekTo(const Duration(seconds: -5));
      expect(h.seeks.last, Duration.zero);
      h.demo.detachPlayer();
      expect(() => h.demo.seekTo(const Duration(seconds: 1)),
          throwsA(isA<StateError>()));
      h.dispose();
    });

    testWidgets('real Live mode exposes no seeking, only buffer information',
        (tester) async {
      final h = _Harness(live: true);
      await _start(tester, h);
      expect(_k('console-timeline'), findsNothing);
      expect(_k('console-live-buffer'), findsOneWidget);
      expect(find.textContaining('ROLLING BUFFER'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('Rider Lock and view modes', () {
    testWidgets('Demo: selecting a target is obvious and labelled simulated',
        (tester) async {
      final h = _Harness();
      await _start(tester, h);
      await tester.tap(_k('console-rider-lock'));
      await tester.pump();
      expect(_k('console-rider-picker'), findsOneWidget);
      expect(find.text('Simulated targets — not detections'), findsOneWidget);

      await tester.tap(_k('console-target-other'));
      await tester.pump();
      expect(h.demo.riderLock.value, 'other');
      expect(find.text('LOCK · SIM'), findsOneWidget);
      // The selected row shows a lock icon, the other a radio circle.
      expect(
          find.descendant(
              of: _k('console-target-other'),
              matching: find.byIcon(Icons.lock)),
          findsOneWidget);
      expect(
          find.descendant(
              of: _k('console-target-rider'),
              matching: find.byIcon(Icons.radio_button_unchecked)),
          findsOneWidget);

      await tester.tap(_k('console-clear-lock'));
      await tester.pump();
      expect(h.demo.riderLock.value, isNull);
      expect(find.text('NO LOCK'), findsOneWidget);
      expect(h.control.commands, isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Core: no target data, so no lock is offered or claimed',
        (tester) async {
      final h = _Harness(live: true);
      await _start(tester, h);
      expect(find.text('LOCK · N/A'), findsOneWidget);
      await tester.tap(_k('console-rider-lock'));
      await tester.pump();
      expect(find.textContaining('Not available yet'), findsOneWidget);
      expect(find.text('Simulated targets — not detections'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'Demo view modes are local; Core sends set_control_mode and has no RAW',
        (tester) async {
      final demo = _Harness();
      await _start(tester, demo);
      await tester.tap(_k('console-mode-raw'));
      await tester.pump();
      expect(demo.demo.viewMode.value, DemoViewMode.raw);
      await tester.tap(_k('console-mode-manual'));
      await tester.pump();
      expect(demo.demo.viewMode.value, DemoViewMode.manual);
      expect(demo.control.commands, isEmpty);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Core view modes', (tester) async {
      final core = _Harness(live: true);
      await _start(tester, core);
      await tester.tap(_k('console-mode-raw'));
      await tester.pump();
      expect(core.control.commands, isEmpty,
          reason: 'RAW is unavailable in Core');
      await tester.tap(_k('console-mode-manual'));
      await tester.pump();
      expect(core.control.commands, contains('set_control_mode'));
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('telemetry HUD', () {
    testWidgets(
        'expands on demand and marks unavailable data instead of inventing it',
        (tester) async {
      final h = _Harness();
      await _start(tester, h);
      expect(_k('console-telemetry-panel'), findsNothing);
      await tester.tap(_k('console-hud-toggle'));
      await tester.pump();
      expect(_k('console-telemetry-panel'), findsOneWidget);
      expect(find.textContaining('unavailable'), findsWidgets);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('LandscapeConsoleController', () {
    testWidgets('idle hides controls, interact restores, clean view is sticky',
        (tester) async {
      final c = LandscapeConsoleController(
          idleDelay: const Duration(seconds: 1),
          thumbnailDuration: const Duration(seconds: 2));
      addTearDown(c.dispose);
      expect(c.controlsVisible, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(c.controlsVisible, isFalse);
      c.interact();
      expect(c.controlsVisible, isTrue);
      c.enterCleanView();
      expect(c.controlsVisible, isFalse);
      c.interact(); // a pinch or drag must not restore the HUD
      expect(c.cleanView, isTrue);
      c.exitCleanView();
      expect(c.controlsVisible, isTrue);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
