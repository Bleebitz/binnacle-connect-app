// Focused tests for the WHEP live-view HUD's pure logic: telemetry
// packet parsing (must degrade gracefully on malformed/dropped packets,
// never throw) and the normalized-bbox -> canvas-rect coordinate
// transform (must stay correct across arbitrary screen aspect ratios).
// Deliberately no widget pump here — flutter_webrtc's native renderer
// can't be constructed in a plain `flutter test` host, so the transport
// (whep_client.dart) is exercised only through this pure logic, not
// end-to-end.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:binnacle_connect/features/live_view/hud_painter.dart';
import 'package:binnacle_connect/features/live_view/telemetry_frame.dart';

void main() {
  group('TelemetryFrame.tryParse', () {
    test('parses a well-formed frame with multiple riders', () {
      final frame = TelemetryFrame.tryParse({
        'frame_seq': 42,
        'state': 'TRACKING',
        'riders': [
          {
            'track_id': '7',
            'confidence': 0.91,
            'bbox': [0.1, 0.2, 0.3, 0.4],
          },
          {
            'track_id': '9',
            'confidence': 0.5,
            'bbox': [0.5, 0.5, 0.2, 0.2],
          },
        ],
      });

      expect(frame, isNotNull);
      expect(frame!.frameSeq, 42);
      expect(frame.state, TrackingState.tracking);
      expect(frame.riders, hasLength(2));
      expect(frame.riders[0].trackId, '7');
      expect(frame.riders[0].confidence, closeTo(0.91, 1e-9));
      expect(frame.riders[0].bbox.x, 0.1);
    });

    test('maps every documented state string', () {
      for (final entry in {
        'TRACKING': TrackingState.tracking,
        'COASTING': TrackingState.coasting,
        'FALL_CANDIDATE': TrackingState.fallCandidate,
        'LOST': TrackingState.lost,
      }.entries) {
        final frame = TelemetryFrame.tryParse(
            {'frame_seq': 1, 'state': entry.key, 'riders': []});
        expect(frame!.state, entry.value, reason: entry.key);
      }
    });

    test('unrecognized state string degrades to unknown, not a throw', () {
      final frame = TelemetryFrame.tryParse(
          {'frame_seq': 1, 'state': 'SOMETHING_NEW', 'riders': []});
      expect(frame!.state, TrackingState.unknown);
    });

    test('missing frame_seq is dropped (returns null), no throw', () {
      final frame = TelemetryFrame.tryParse({'state': 'TRACKING', 'riders': []});
      expect(frame, isNull);
    });

    test('a rider with a malformed bbox is skipped, others still parse', () {
      final frame = TelemetryFrame.tryParse({
        'frame_seq': 3,
        'state': 'TRACKING',
        'riders': [
          {'track_id': 'bad', 'confidence': 0.9, 'bbox': [0.1, 0.2]}, // wrong length
          {
            'track_id': 'good',
            'confidence': 0.8,
            'bbox': [0.0, 0.0, 1.0, 1.0],
          },
        ],
      });
      expect(frame, isNotNull);
      expect(frame!.riders, hasLength(1));
      expect(frame.riders.single.trackId, 'good');
    });

    test('non-list riders field yields an empty rider list, not a throw', () {
      final frame = TelemetryFrame.tryParse(
          {'frame_seq': 5, 'state': 'TRACKING', 'riders': 'not-a-list'});
      expect(frame, isNotNull);
      expect(frame!.riders, isEmpty);
    });

    test('confidence outside [0,1] is clamped rather than propagated raw',
        () {
      final frame = TelemetryFrame.tryParse({
        'frame_seq': 6,
        'state': 'TRACKING',
        'riders': [
          {
            'track_id': '1',
            'confidence': 1.4,
            'bbox': [0.0, 0.0, 0.1, 0.1],
          },
        ],
      });
      expect(frame!.riders.single.confidence, 1.0);
    });
  });

  group('mapNormalizedBoxToCanvas', () {
    const bbox = NormalizedBBox(x: 0.25, y: 0.25, w: 0.5, h: 0.5);

    test('exact aspect-ratio match scales directly, no offset', () {
      final rect = mapNormalizedBoxToCanvas(
        bbox: bbox,
        canvasSize: const Size(1600, 900), // 16:9, matches video
        videoAspectRatio: 16 / 9,
      );
      expect(rect.left, closeTo(400, 0.001));
      expect(rect.top, closeTo(225, 0.001));
      expect(rect.width, closeTo(800, 0.001));
      expect(rect.height, closeTo(450, 0.001));
    });

    test('taller/narrower canvas than video letterboxes top and bottom', () {
      // A 16:9 video shown in a square canvas leaves equal bars top+bottom.
      final rect = mapNormalizedBoxToCanvas(
        bbox: const NormalizedBBox(x: 0, y: 0, w: 1, h: 1),
        canvasSize: const Size(900, 900),
        videoAspectRatio: 16 / 9,
      );
      // content height = 900/(16/9) = 506.25; vertical bar on each side.
      const expectedContentHeight = 900 / (16 / 9);
      const expectedOffsetY = (900 - expectedContentHeight) / 2;
      expect(rect.top, closeTo(expectedOffsetY, 0.01));
      expect(rect.left, closeTo(0, 0.01));
      expect(rect.width, closeTo(900, 0.01));
      expect(rect.height, closeTo(expectedContentHeight, 0.01));
    });

    test('wider canvas than video pillarboxes left and right', () {
      // A 9:16 (portrait) video shown in a wide landscape canvas.
      final rect = mapNormalizedBoxToCanvas(
        bbox: const NormalizedBBox(x: 0, y: 0, w: 1, h: 1),
        canvasSize: const Size(1600, 900),
        videoAspectRatio: 9 / 16,
      );
      const expectedContentWidth = 900 * (9 / 16);
      const expectedOffsetX = (1600 - expectedContentWidth) / 2;
      expect(rect.left, closeTo(expectedOffsetX, 0.01));
      expect(rect.top, closeTo(0, 0.01));
      expect(rect.height, closeTo(900, 0.01));
      expect(rect.width, closeTo(expectedContentWidth, 0.01));
    });

    test('a corner box stays fully inside the mapped content rect', () {
      final rect = mapNormalizedBoxToCanvas(
        bbox: const NormalizedBBox(x: 0.9, y: 0.9, w: 0.1, h: 0.1),
        canvasSize: const Size(390, 844), // a small portrait phone
        videoAspectRatio: 16 / 9,
      );
      expect(rect.right, lessThanOrEqualTo(390.01));
      expect(rect.bottom, lessThanOrEqualTo(844.01));
    });
  });

  group('colorForState / labelForState', () {
    test('every state maps to a distinct color and a non-empty label', () {
      final colors = <Color>{};
      for (final state in TrackingState.values) {
        final color = colorForState(state);
        colors.add(color);
        expect(labelForState(state), isNotEmpty);
      }
      // tracking/coasting/fallCandidate must be visually distinguishable;
      // lost/unknown are deliberately allowed to share the neutral color.
      expect(colors.length, greaterThanOrEqualTo(4));
    });
  });
}
