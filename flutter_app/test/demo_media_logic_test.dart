// Pure logic for the recorded-Demo media actions: zoom, highlight window,
// serialization, provenance, and the Demo/Core type separation.

import 'package:flutter_test/flutter_test.dart';

import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/services/camera_media_source.dart';
import 'package:binnacle_connect/core/services/demo_media.dart';
import 'package:binnacle_connect/core/services/webrtc_service.dart';

const _src = Duration(seconds: 130);
const _pre = Duration(seconds: 15);
const _post = Duration(seconds: 30);

HighlightWindow _window(int atSeconds, {Duration source = _src}) =>
    HighlightWindow.compute(
      position: Duration(seconds: atSeconds),
      preRoll: _pre,
      postRoll: _post,
      sourceDuration: source,
    );

void main() {
  group('demo zoom', () {
    test('starts at 1.0x and steps by 0.5x', () {
      final z = DemoZoom();
      expect(z.value, 1.0);
      z.zoomIn();
      expect(z.value, 1.5);
      z.zoomIn();
      expect(z.value, 2.0);
      z.zoomOut();
      expect(z.value, 1.5);
    });

    test('clamps at the minimum and maximum', () {
      final z = DemoZoom();
      z.zoomOut();
      expect(z.value, DemoZoom.min);
      expect(z.canZoomOut, isFalse);
      for (var i = 0; i < 20; i++) {
        z.zoomIn();
      }
      expect(z.value, DemoZoom.max);
      expect(z.value, 4.0);
      expect(z.canZoomIn, isFalse);
      z.zoomIn();
      expect(z.value, 4.0);
    });

    test('pinch values are clamped and notify listeners', () {
      final z = DemoZoom();
      final seen = <double>[];
      z.addListener(() => seen.add(z.value));
      z.setZoom(2.7);
      z.setZoom(99);
      z.setZoom(0.1);
      expect(seen, [2.7, 4.0, 1.0]);
    });

    test('a repeated clamped value does not spam listeners', () {
      final z = DemoZoom();
      var notified = 0;
      z.addListener(() => notified++);
      z.zoomOut(); // already at minimum
      expect(notified, 0);
    });
  });

  group('highlight capture window', () {
    test('mid-source: pre-roll before and post-roll after the playhead', () {
      final w = _window(60);
      expect(w.start, const Duration(seconds: 45));
      expect(w.end, const Duration(seconds: 90));
      expect(w.length, const Duration(seconds: 45));
    });

    test('near the beginning the start clamps to zero', () {
      final w = _window(5);
      expect(w.start, Duration.zero);
      expect(w.end, const Duration(seconds: 35));
      expect(w.length, const Duration(seconds: 35));
    });

    test('at exactly zero', () {
      final w = _window(0);
      expect(w.start, Duration.zero);
      expect(w.end, const Duration(seconds: 30));
    });

    test('near the end the end clamps to the source length', () {
      final w = _window(120);
      expect(w.start, const Duration(seconds: 105));
      expect(w.end, _src);
      expect(w.length, const Duration(seconds: 25));
    });

    test('on the very last frame the clip is still non-empty', () {
      final w = _window(130);
      expect(w.end, _src);
      expect(w.start, const Duration(seconds: 115));
      expect(w.length, greaterThan(Duration.zero));
    });

    test('a playhead outside the source is clamped into it', () {
      expect(_window(500).end, _src);
      expect(
        HighlightWindow.compute(
          position: const Duration(seconds: -4),
          preRoll: _pre,
          postRoll: _post,
          sourceDuration: _src,
        ).start,
        Duration.zero,
      );
    });

    test('zero roll at the end still yields at least the minimum length', () {
      final w = HighlightWindow.compute(
        position: _src,
        preRoll: Duration.zero,
        postRoll: Duration.zero,
        sourceDuration: _src,
      );
      expect(w.length, const Duration(seconds: 1));
      expect(w.end, _src);
    });

    test('a source shorter than the roll is covered whole', () {
      final w = _window(3, source: const Duration(seconds: 10));
      expect(w.start, Duration.zero);
      expect(w.end, const Duration(seconds: 10));
    });

    test('time labels', () {
      expect(formatDemoTime(const Duration(seconds: 65)), '1:05');
      expect(formatDemoTime(Duration.zero), '0:00');
    });
  });

  group('clip provenance and serialization', () {
    const segment = MediaSegment(
      assetPath: 'assets/demo/gopro_dev_footage.mp4',
      start: Duration(seconds: 45),
      end: Duration(seconds: 90),
    );

    test('a demo highlight round-trips through local JSON', () {
      final clip = Clip(
        id: 'demo-hl-1',
        title: 'Highlight — 0:45–1:30',
        duration: segment.length,
        kind: ClipKind.highlight,
        riderId: 'levi',
        capturedAt: DateTime.utc(2026, 9, 18, 12),
        origin: ClipOrigin.demoSegment,
        segment: segment,
        signed: false,
        gpsAttached: false,
      );
      final back = Clip.tryFromLocalJson(clip.toLocalJson())!;
      expect(back.origin, ClipOrigin.demoSegment);
      expect(back.segment, segment);
      expect(back.duration, const Duration(seconds: 45));
      expect(back.isDemoOrigin, isTrue);
      expect(back.mediaUrl, isNull);
    });

    test('a demo snapshot round-trips through local JSON', () {
      final clip = Clip(
        id: 'demo-snap-1',
        title: 'Snapshot — 1:02',
        duration: Duration.zero,
        kind: ClipKind.photo,
        riderId: 'levi',
        capturedAt: DateTime.utc(2026, 9, 18, 12),
        origin: ClipOrigin.demoLocalCapture,
        localPath: '/data/demo_media/snapshot_1.jpg',
        thumbnailPath: '/data/demo_media/snapshot_1.jpg',
      );
      final back = Clip.tryFromLocalJson(clip.toLocalJson())!;
      expect(back.origin, ClipOrigin.demoLocalCapture);
      expect(back.localPath, '/data/demo_media/snapshot_1.jpg');
      expect(back.kind, ClipKind.photo);
    });

    test('malformed or foreign local records are dropped, not shown', () {
      expect(Clip.tryFromLocalJson(null), isNull);
      expect(Clip.tryFromLocalJson('nope'), isNull);
      expect(Clip.tryFromLocalJson({'id': 'x', 'kind': 'photo'}), isNull);
      // A segment clip without a valid segment is unusable.
      expect(
        Clip.tryFromLocalJson(
            {'id': 'x', 'kind': 'highlight', 'origin': 'demoSegment'}),
        isNull,
      );
      expect(
        Clip.tryFromLocalJson({
          'id': 'x',
          'kind': 'highlight',
          'origin': 'demoSegment',
          'segment': {'asset_path': 'a', 'start_ms': 9000, 'end_ms': 1000},
        }),
        isNull,
        reason: 'end before start',
      );
    });

    test('a local record can never claim Core origin', () {
      expect(
        Clip.tryFromLocalJson({
          'id': 'x',
          'kind': 'highlight',
          'origin': 'core',
          'segment': segment.toJson(),
        }),
        isNull,
      );
    });

    test('Core JSON parsing is unchanged and always yields Core origin', () {
      final clip = Clip.fromJson({
        'id': 'c1',
        'title': 'Core clip',
        'duration_s': 12,
        'kind': 'highlight',
        'media_url': 'https://core.example/media/c1.mp4',
        // Demo-only fields in a Core payload must be ignored.
        'origin': 'demoSegment',
        'segment': segment.toJson(),
        'local_path': '/etc/hosts',
      });
      expect(clip.origin, ClipOrigin.core);
      expect(clip.isDemoOrigin, isFalse);
      expect(clip.segment, isNull);
      expect(clip.localPath, isNull);
      expect(clip.mediaUrl, 'https://core.example/media/c1.mp4');
    });

    test('copyWith keeps provenance', () {
      final clip = Clip(
        id: 'demo-hl-2',
        title: 't',
        duration: segment.length,
        kind: ClipKind.highlight,
        riderId: 'levi',
        capturedAt: DateTime.utc(2026),
        origin: ClipOrigin.demoSegment,
        segment: segment,
      );
      final fav = clip.copyWith(favorite: true);
      expect(fav.origin, ClipOrigin.demoSegment);
      expect(fav.segment, segment);
      expect(fav.favorite, isTrue);
    });
  });

  group('demo vs Core separation', () {
    late WebRtcService webRtc;
    setUp(() => webRtc = WebRtcService(renderer: SimulatedVideoRenderer()));
    tearDown(() => webRtc.dispose());

    test('only the recorded demo source exposes local media controls', () {
      final demo = CameraMediaSource.forMode(demo: true, webRtc: webRtc);
      final core = CameraMediaSource.forMode(demo: false, webRtc: webRtc);
      addTearDown(demo.dispose);
      addTearDown(core.dispose);
      expect(demo, isA<DemoMediaControls>());
      expect(core, isNot(isA<DemoMediaControls>()));
    });

    test(
        'the recorded video position is the single clock for Track state and capture',
        () async {
      final source = DemoRecordedCameraSource();
      addTearDown(source.dispose);

      // Not ready: capture must fail rather than invent a position.
      await expectLater(source.readPlaybackPosition(), throwsStateError);

      var playerPosition = const Duration(seconds: 60);
      source.attachPlayer(
        readPosition: () async => playerPosition,
        duration: _src,
      );
      expect(source.sourceDuration, _src);

      expect(await source.readPlaybackPosition(), const Duration(seconds: 60));
      expect(source.trackState.value.phase, VisionTrackPhase.tracking);

      playerPosition = const Duration(seconds: 125);
      expect(await source.readPlaybackPosition(), const Duration(seconds: 125));
      expect(source.trackState.value.phase, VisionTrackPhase.occluded,
          reason:
              'reading the position for capture also drives the Track reducer');

      source.detachPlayer();
      await expectLater(source.readPlaybackPosition(), throwsStateError);
    });

    test('demo zoom is local state on the source', () {
      final source = DemoRecordedCameraSource();
      addTearDown(source.dispose);
      source.zoom.zoomIn();
      expect(source.zoom.value, 1.5);
    });
  });
}
