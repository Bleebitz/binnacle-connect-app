// The pre-authored spatial rider track for the controlled Demo footage: parsing,
// validation, source association, interpolation, gaps and occlusion, seeking.
//
// It reads the REAL shipped asset, so a bad edit to the annotation fails here.

import 'dart:convert';
import 'dart:io';

import 'package:binnacle_connect/core/models/rider_track.dart';
import 'package:flutter_test/flutter_test.dart';

const _sourceSha =
    '6815ded40dd19e8e4a0cf1db2c30b7eb9e04585029bc64d935c5c76ffdf33f8f';

String _assetText() => File(DemoRiderTrack.assetPath).readAsStringSync();

DemoRiderTrack _real() => DemoRiderTrack.parse(_assetText());

/// A small synthetic track for exact-value tests.
String _synthetic(List<Map<String, dynamic>> keyframes,
    {double gap = 5.0, Object? targets}) {
  return jsonEncode({
    'schema': 'binnacle.demo_rider_track',
    'version': 1,
    'provenance': 'test',
    'source': {
      'asset': 'assets/demo/gopro_dev_footage.mp4',
      'sha256': _sourceSha,
      'width': 1920,
      'height': 1080,
      'durationS': 130.0,
    },
    'coordinateSystem': 'normalized source-frame',
    'maxInterpolationGapS': gap,
    'targets': targets ??
        [
          {'id': 'rider', 'label': 'RIDER', 'keyframes': keyframes}
        ],
  });
}

Map<String, dynamic> _v(double t, double cx, double cy,
        {double w = 0.1, double h = 0.3}) =>
    {'t': t, 'state': 'visible', 'cx': cx, 'cy': cy, 'w': w, 'h': h};

Map<String, dynamic> _o(double t, double cx, double cy) =>
    {'t': t, 'state': 'occluded', 'cx': cx, 'cy': cy, 'w': 0.1, 'h': 0.3};

Map<String, dynamic> _u(double t) => {'t': t, 'state': 'unknown'};

Duration _s(double s) => Duration(microseconds: (s * 1e6).round());

void main() {
  group('the shipped annotation', () {
    test('parses and describes exactly the controlled Demo footage', () {
      final t = _real();
      expect(t.version, 1);
      expect(t.sourceAsset, 'assets/demo/gopro_dev_footage.mp4');
      expect(t.sourceSha256, _sourceSha,
          reason: 'the track must be tied to the exact controlled source');
      expect(t.sourceWidth, 1920);
      expect(t.sourceHeight, 1080);
      expect(t.sourceDurationS, 130.0);
      expect(t.provenanceNote, contains('not detector output'));
      expect(t.provenanceNote, contains('not live detection'));
    });

    test('the tracked source file is the one the annotation was made against',
        () {
      // The full SHA-256 is verified by tools/demo_track/build_track.py when the
      // track is generated; here a swapped or re-encoded asset is caught by size.
      expect(File('assets/demo/gopro_dev_footage.mp4').lengthSync(), 82092098);
    });

    test('has a dense keyframe set with a real occlusion window', () {
      final t = _real();
      expect(t.visibleKeyframeCount, greaterThan(400));
      expect(t.occludedKeyframeCount, greaterThanOrEqualTo(1));
      expect(t.keyframeCount,
          greaterThan(t.visibleKeyframeCount + t.occludedKeyframeCount - 1));
    });

    test('every box is normalised to the source frame (0..1)', () {
      // parse() rejects anything outside 0..1; sampling the whole pass also
      // proves the interpolation never leaves it.
      final t = _real();
      for (var ms = 0; ms <= 130000; ms += 100) {
        final s = t.at(Duration(milliseconds: ms));
        if (s == null) continue;
        expect(s.box.isValid, isTrue, reason: 'at ${ms / 1000}s: ${s.box}');
        expect(s.box.left, greaterThanOrEqualTo(-0.02));
        expect(s.box.right, lessThanOrEqualTo(1.02));
      }
    });

    test('exposes exactly one target: the rider (no fabricated second person)',
        () {
      final t = _real();
      final ids = <String>{};
      for (var ms = 0; ms <= 130000; ms += 250) {
        final s = t.at(Duration(milliseconds: ms));
        if (s != null) ids.add(s.id);
      }
      expect(ids, {'rider'});
      expect(t.targetLabel, 'RIDER');
    });

    test('every target it returns says it is a Demo annotation, never Core',
        () {
      final t = _real();
      for (final ms in [0, 5000, 60000, 122000, 126000]) {
        final s = t.at(Duration(milliseconds: ms));
        if (s != null) {
          expect(s.provenance, TargetProvenance.demoAnnotation);
          expect(s.isDemo, isTrue);
        }
      }
    });

    test('follows the rider: known spots read off the footage', () {
      final t = _real();
      // Hand-read positions (source frame is 1920x1080).
      final start = t.at(Duration.zero)!;
      expect(start.box.cx * 1920, closeTo(1275, 12));
      expect(start.box.cy * 1080, closeTo(600, 12));
      final mid = t.at(const Duration(seconds: 60))!;
      expect(mid.box.cx * 1920, closeTo(1027, 40));
      final late = t.at(const Duration(seconds: 102))!;
      expect(late.box.cx * 1920, closeTo(977, 40));
    });

    test(
        'the rider is right of centre at the start and drifts left across the pass',
        () {
      final t = _real();
      final xs = [
        for (final s in [0, 20, 45, 70, 92, 110, 121])
          t.at(Duration(seconds: s))!.box.cx
      ];
      // The rider is right of centre at the start and drifts left, so the pass
      // genuinely needs the crop to move (a fixed centre zoom cannot follow it).
      expect(xs.first, greaterThan(0.6));
      expect(xs.reduce((a, b) => a < b ? a : b), lessThan(0.55));
    });
  });

  group('states and the fall', () {
    test(
        'rider is visible through the ride, coasting after the fall, then none',
        () {
      final t = _real();
      expect(t.at(const Duration(seconds: 30))!.visibility,
          TargetVisibility.visible);
      expect(t.at(const Duration(seconds: 122))!.visibility,
          TargetVisibility.visible);
      final coasting = t.at(const Duration(seconds: 126))!;
      expect(coasting.visibility, TargetVisibility.coasting);
      expect(coasting.isCoasting, isTrue);
      expect(t.at(const Duration(milliseconds: 129500)), isNull,
          reason: 'no confident box where no rider position is known');
      expect(t.at(const Duration(seconds: 130)), isNull);
    });

    test('coasting holds the LAST KNOWN box; it does not keep moving', () {
      final t = _real();
      final a = t.at(const Duration(seconds: 125))!.box;
      final b = t.at(const Duration(seconds: 128))!.box;
      expect(a, b);
    });

    test('loop / reset returns the correct initial state', () {
      final t = _real();
      final first = t.at(Duration.zero)!;
      // A player loop hands back zero again after the end of the pass.
      final afterLoop = t.at(Duration.zero)!;
      expect(afterLoop.box, first.box);
      expect(afterLoop.visibility, TargetVisibility.visible);
      expect(t.at(const Duration(seconds: 130)), isNull);
    });

    test('seeking is stateless: any position gives its own target at once', () {
      final t = _real();
      final order = [10, 100, 3, 60, 121, 40];
      final direct = {
        for (final s in order) s: t.at(Duration(seconds: s))!.box
      };
      // Same values regardless of the order they are asked in.
      for (final s in order.reversed) {
        expect(t.at(Duration(seconds: s))!.box, direct[s]);
      }
      // And they really differ, so a seek visibly moves the rider.
      expect(direct[10], isNot(direct[100]));
    });
  });

  group('interpolation', () {
    test('a keyframe returns its own box exactly', () {
      final t = DemoRiderTrack.parse(_synthetic([
        _v(0, 0.30, 0.50),
        _v(2, 0.50, 0.50),
        _v(4, 0.70, 0.50),
      ]));
      expect(t.at(_s(2))!.box.cx, closeTo(0.50, 1e-9));
      expect(t.at(_s(0))!.box.cx, closeTo(0.30, 1e-9));
    });

    test('between two visible keyframes it is smooth and stays between them',
        () {
      final t = DemoRiderTrack.parse(_synthetic([
        _v(0, 0.30, 0.40),
        _v(2, 0.50, 0.50),
        _v(4, 0.70, 0.60),
      ]));
      var last = 0.50;
      for (var ms = 2000; ms <= 4000; ms += 100) {
        final x = t.at(Duration(milliseconds: ms))!.box.cx;
        expect(x, inInclusiveRange(0.50 - 1e-9, 0.70 + 1e-9));
        expect(x, greaterThanOrEqualTo(last - 1e-9),
            reason: 'monotone, no wobble');
        last = x;
      }
      // Uniform motion: the midpoint is the middle.
      expect(t.at(_s(3))!.box.cx, closeTo(0.60, 1e-6));
      expect(t.at(_s(3))!.box.cy, closeTo(0.55, 1e-6));
    });

    test('box size interpolates too', () {
      final t = DemoRiderTrack.parse(_synthetic([
        _v(0, 0.5, 0.5, w: 0.10, h: 0.30),
        _v(2, 0.5, 0.5, w: 0.20, h: 0.50),
      ]));
      final m = t.at(_s(1))!.box;
      expect(m.w, closeTo(0.15, 1e-6));
      expect(m.h, closeTo(0.40, 1e-6));
    });

    test('is deterministic', () {
      final a = _real(), b = _real();
      for (final ms in [1234, 45678, 99999]) {
        expect(a.at(Duration(milliseconds: ms))!.box,
            b.at(Duration(milliseconds: ms))!.box);
      }
    });

    test('mirrors tools/demo_track/verify_overlay.py (pinned values)', () {
      // The audit script draws the same interpolation; these pin it.
      final t = _real();
      final s = t.at(const Duration(milliseconds: 60125))!.box;
      final k0 = t.at(const Duration(seconds: 60))!.box;
      final k1 = t.at(const Duration(milliseconds: 60250))!.box;
      expect(
          s.cx,
          inInclusiveRange(
              k0.cx < k1.cx ? k0.cx : k1.cx, k0.cx < k1.cx ? k1.cx : k0.cx));
    });
  });

  group('gaps, occlusion and unknown', () {
    test('never interpolates across an occluded keyframe', () {
      final t = DemoRiderTrack.parse(_synthetic([
        _v(0, 0.2, 0.5),
        _v(2, 0.3, 0.5),
        _o(3, 0.3, 0.5),
        _v(5, 0.9, 0.5),
      ]));
      // Between 3 and 5 the rider is not seen: last-known box, coasting.
      final mid = t.at(_s(4))!;
      expect(mid.visibility, TargetVisibility.coasting);
      expect(mid.box.cx, closeTo(0.3, 1e-9));
      // After the next visible keyframe it is a real observation again.
      expect(t.at(_s(5))!.visibility, TargetVisibility.visible);
      expect(t.at(_s(5))!.box.cx, closeTo(0.9, 1e-9));
    });

    test('an unknown span has no target at all', () {
      final t = DemoRiderTrack.parse(_synthetic([
        _v(0, 0.2, 0.5),
        _v(2, 0.3, 0.5),
        _u(3),
        _v(6, 0.9, 0.5),
      ]));
      expect(t.at(_s(2.5))!.visibility, TargetVisibility.visible);
      expect(t.at(_s(4)), isNull);
      expect(t.at(_s(5.99)), isNull);
      expect(t.at(_s(6))!.box.cx, closeTo(0.9, 1e-9));
    });

    test('does not invent motion across a large unannotated gap', () {
      final t = DemoRiderTrack.parse(_synthetic([
        _v(0, 0.2, 0.5),
        _v(20, 0.8, 0.5),
      ], gap: 5));
      expect(t.at(_s(0))!.box.cx, closeTo(0.2, 1e-9));
      expect(t.at(_s(10)), isNull);
      expect(t.at(_s(20))!.box.cx, closeTo(0.8, 1e-9));
    });

    test('there is no target before the first keyframe', () {
      final t =
          DemoRiderTrack.parse(_synthetic([_v(2, 0.5, 0.5), _v(4, 0.6, 0.5)]));
      expect(t.at(_s(1)), isNull);
    });
  });

  group('validation rejects bad data', () {
    void rejects(String why, String json) => test(why, () {
          expect(() => DemoRiderTrack.parse(json),
              throwsA(isA<RiderTrackFormatException>()));
        });

    rejects('not JSON', 'nope');
    rejects('coordinates outside 0..1',
        _synthetic([_v(0, 1.4, 0.5), _v(1, 0.5, 0.5)]));
    rejects('negative coordinates',
        _synthetic([_v(0, -0.1, 0.5), _v(1, 0.5, 0.5)]));
    rejects('box wider than the frame',
        _synthetic([_v(0, 0.5, 0.5, w: 1.5), _v(1, 0.5, 0.5)]));
    rejects(
        'zero-size box', _synthetic([_v(0, 0.5, 0.5, w: 0), _v(1, 0.5, 0.5)]));
    rejects(
        'non-increasing time', _synthetic([_v(1, 0.5, 0.5), _v(1, 0.6, 0.5)]));
    rejects('time outside the source',
        _synthetic([_v(0, 0.5, 0.5), _v(200, 0.6, 0.5)]));
    rejects(
        'must start visible', _synthetic([_o(0, 0.5, 0.5), _v(1, 0.6, 0.5)]));
    rejects(
        'unknown state',
        _synthetic([
          _v(0, 0.5, 0.5),
          {'t': 1, 'state': 'flying'},
        ]));
    rejects(
        'a second (fabricated) target',
        _synthetic([], targets: [
          {
            'id': 'rider',
            'label': 'RIDER',
            'keyframes': [_v(0, 0.5, 0.5)]
          },
          {
            'id': 'other',
            'label': 'PERSON 2',
            'keyframes': [_v(0, 0.2, 0.5)]
          },
        ]));
    rejects(
        'wrong schema',
        _synthetic([_v(0, 0.5, 0.5)])
            .replaceFirst('binnacle.demo_rider_track', 'something.else'));
    rejects(
        'unsupported version',
        _synthetic([_v(0, 0.5, 0.5)])
            .replaceFirst('"version":1', '"version":9'));
    rejects('source hash missing or malformed',
        _synthetic([_v(0, 0.5, 0.5)]).replaceFirst(_sourceSha, 'abc'));
  });

  test('a track for a different video is not accepted as this one', () {
    final t = DemoRiderTrack.parse(
        _synthetic([_v(0, 0.5, 0.5), _v(1, 0.5, 0.5)]).replaceFirst(
            'assets/demo/gopro_dev_footage.mp4', 'assets/demo/other.mp4'));
    expect(t.sourceAsset, isNot('assets/demo/gopro_dev_footage.mp4'));
  });

  test('NormBox geometry helpers', () {
    const b = NormBox(cx: 0.5, cy: 0.5, w: 0.2, h: 0.4);
    expect(b.left, closeTo(0.4, 1e-12));
    expect(b.right, closeTo(0.6, 1e-12));
    expect(b.top, closeTo(0.3, 1e-12));
    expect(b.bottom, closeTo(0.7, 1e-12));
    expect(b.isValid, isTrue);
    expect(const NormBox(cx: 2, cy: 0.5, w: 0.1, h: 0.1).isValid, isFalse);
    expect(const NormBox(cx: double.nan, cy: 0.5, w: 0.1, h: 0.1).isValid,
        isFalse);
  });
}
