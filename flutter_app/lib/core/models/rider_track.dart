// Spatial rider targets: the contract between whatever knows where the rider is
// and the Live UI that frames and marks them.
//
// TWO different things live here and must not be confused:
//
//  * [TrackTargetState] is the forward-compatible CONTRACT. Real Binnacle Track
//    (Jetson/DeepStream, via the Core) is expected to supply the same concept
//    later: a target id, a box in normalised SOURCE-frame coordinates, a
//    visibility state and provenance. Nothing supplies real ones today.
//
//  * [DemoRiderTrack] is a pre-authored spatial rider track for ONE controlled
//    recorded Demo video. It is a hand-read annotation of that footage
//    (assets/demo/gopro_dev_rider_track_v1.json), not detector output. It is not
//    live detection, AI inference, Jetson tracking, or Core Rider Lock, and the
//    UI says so.
//
// Coordinates are normalised to the SOURCE frame (0..1, origin top-left), never
// to a screen, so they stay valid in portrait, landscape, on any device, and
// under any BoxFit, zoom or pan.

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A box in normalised source-frame coordinates: centre and size, all 0..1.
@immutable
class NormBox {
  final double cx;
  final double cy;
  final double w;
  final double h;

  const NormBox({
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
  });

  double get left => cx - w / 2;
  double get top => cy - h / 2;
  double get right => cx + w / 2;
  double get bottom => cy + h / 2;

  /// True when the centre is inside the frame and the box has a positive size
  /// that fits it. Used to reject corrupt data, never to clip a live one.
  bool get isValid =>
      cx.isFinite &&
      cy.isFinite &&
      w.isFinite &&
      h.isFinite &&
      cx >= 0 &&
      cx <= 1 &&
      cy >= 0 &&
      cy <= 1 &&
      w > 0 &&
      w <= 1 &&
      h > 0 &&
      h <= 1;

  @override
  bool operator ==(Object other) =>
      other is NormBox &&
      other.cx == cx &&
      other.cy == cy &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(cx, cy, w, h);

  @override
  String toString() => 'NormBox(cx: $cx, cy: $cy, w: $w, h: $h)';
}

/// How much to trust a target's box right now.
enum TargetVisibility {
  /// The target is seen; the box is a current observation.
  visible,

  /// The target was lost recently; the box is its LAST KNOWN position and must be
  /// drawn as such (dashed, reduced), never as a confirmed detection.
  coasting,
}

/// Who produced a target. The UI labels Demo targets so they can never pass for
/// real Track output.
enum TargetProvenance {
  /// Pre-authored annotation of the controlled recorded Demo footage.
  demoAnnotation,

  /// Real Binnacle Track output from the Core. Nothing produces this yet.
  core,
}

/// One tracked target as the Live UI consumes it.
@immutable
class TrackTargetState {
  final String id;
  final String label;
  final NormBox box;
  final TargetVisibility visibility;
  final TargetProvenance provenance;

  /// Optional future semantic role from Track (rider, passenger, swimmer...).
  /// The Demo annotation does not set one.
  final String? role;

  const TrackTargetState({
    required this.id,
    required this.label,
    required this.box,
    required this.visibility,
    required this.provenance,
    this.role,
  });

  bool get isCoasting => visibility == TargetVisibility.coasting;
  bool get isDemo => provenance == TargetProvenance.demoAnnotation;
}

enum _KeyState { visible, occluded, unknown }

class _Keyframe {
  final double t;
  final _KeyState state;
  final NormBox? box;
  const _Keyframe(this.t, this.state, this.box);
}

class RiderTrackFormatException implements Exception {
  final String message;
  RiderTrackFormatException(this.message);
  @override
  String toString() => 'Invalid rider track: $message';
}

/// The pre-authored rider track for the controlled Demo footage.
///
/// Interpolation is deterministic: a tension-scaled cubic Hermite (Catmull-Rom
/// style) between two consecutive `visible` keyframes, and never across an
/// `occluded` or `unknown` keyframe or a gap larger than [maxInterpolationGapS].
/// tools/demo_track/verify_overlay.py implements the same maths for the visual
/// audit; test/rider_track_test.dart pins values so the two cannot drift.
class DemoRiderTrack {
  static const assetPath = 'assets/demo/gopro_dev_rider_track_v1.json';
  static const schema = 'binnacle.demo_rider_track';
  static const supportedVersion = 1;

  /// Hermite tangent scale. Below 1 keeps the curve from overshooting between
  /// keyframes.
  static const _tension = 0.75;

  final int version;
  final String provenanceNote;
  final String sourceAsset;
  final String sourceSha256;
  final int sourceWidth;
  final int sourceHeight;
  final double sourceDurationS;
  final double maxInterpolationGapS;
  final String targetId;
  final String targetLabel;
  final List<_Keyframe> _kfs;

  DemoRiderTrack._({
    required this.version,
    required this.provenanceNote,
    required this.sourceAsset,
    required this.sourceSha256,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.sourceDurationS,
    required this.maxInterpolationGapS,
    required this.targetId,
    required this.targetLabel,
    required List<_Keyframe> keyframes,
  }) : _kfs = keyframes;

  int get keyframeCount => _kfs.length;
  int get visibleKeyframeCount =>
      _kfs.where((k) => k.state == _KeyState.visible).length;
  int get occludedKeyframeCount =>
      _kfs.where((k) => k.state == _KeyState.occluded).length;

  factory DemoRiderTrack.parse(String source) {
    final dynamic root;
    try {
      root = jsonDecode(source);
    } on FormatException catch (e) {
      throw RiderTrackFormatException('not JSON (${e.message})');
    }
    if (root is! Map<String, dynamic>) {
      throw RiderTrackFormatException('root is not an object');
    }
    if (root['schema'] != schema) {
      throw RiderTrackFormatException('unexpected schema ${root['schema']}');
    }
    final version = root['version'];
    if (version != supportedVersion) {
      throw RiderTrackFormatException('unsupported version $version');
    }
    final src = root['source'];
    if (src is! Map<String, dynamic>) {
      throw RiderTrackFormatException('missing source');
    }
    final sha = src['sha256'];
    if (sha is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw RiderTrackFormatException('source.sha256 is not a SHA-256');
    }
    final asset = src['asset'];
    final width = src['width'];
    final height = src['height'];
    final duration = src['durationS'];
    if (asset is! String ||
        width is! int ||
        height is! int ||
        width <= 0 ||
        height <= 0 ||
        duration is! num ||
        duration <= 0) {
      throw RiderTrackFormatException('incomplete source description');
    }
    final gap = root['maxInterpolationGapS'];
    if (gap is! num || gap <= 0) {
      throw RiderTrackFormatException('maxInterpolationGapS is missing');
    }
    final targets = root['targets'];
    if (targets is! List || targets.length != 1) {
      throw RiderTrackFormatException(
          'the Demo track has exactly one annotated target');
    }
    final target = targets.single;
    if (target is! Map<String, dynamic> ||
        target['id'] is! String ||
        target['label'] is! String ||
        target['keyframes'] is! List) {
      throw RiderTrackFormatException('malformed target');
    }
    final frames = <_Keyframe>[];
    double? lastT;
    for (final raw in target['keyframes'] as List) {
      if (raw is! Map<String, dynamic> || raw['t'] is! num) {
        throw RiderTrackFormatException('malformed keyframe $raw');
      }
      final t = (raw['t'] as num).toDouble();
      if (lastT != null && t <= lastT) {
        throw RiderTrackFormatException('keyframes must be strictly increasing '
            'in time (at $t)');
      }
      if (t < 0 || t > duration) {
        throw RiderTrackFormatException(
            'keyframe time $t is outside the source');
      }
      lastT = t;
      final _KeyState state;
      switch (raw['state']) {
        case 'visible':
          state = _KeyState.visible;
        case 'occluded':
          state = _KeyState.occluded;
        case 'unknown':
          state = _KeyState.unknown;
        default:
          throw RiderTrackFormatException(
              'unknown keyframe state ${raw['state']}');
      }
      NormBox? box;
      if (state != _KeyState.unknown) {
        final cx = raw['cx'], cy = raw['cy'], w = raw['w'], h = raw['h'];
        if (cx is! num || cy is! num || w is! num || h is! num) {
          throw RiderTrackFormatException('keyframe at $t has no box');
        }
        box = NormBox(
            cx: cx.toDouble(),
            cy: cy.toDouble(),
            w: w.toDouble(),
            h: h.toDouble());
        if (!box.isValid) {
          throw RiderTrackFormatException(
              'keyframe at $t is not normalised to 0..1: $box');
        }
      }
      frames.add(_Keyframe(t, state, box));
    }
    if (frames.isEmpty || frames.first.state != _KeyState.visible) {
      throw RiderTrackFormatException(
          'the track must start with a visible box');
    }
    return DemoRiderTrack._(
      version: version as int,
      provenanceNote: (root['provenance'] as String?) ?? '',
      sourceAsset: asset,
      sourceSha256: sha,
      sourceWidth: width,
      sourceHeight: height,
      sourceDurationS: duration.toDouble(),
      maxInterpolationGapS: gap.toDouble(),
      targetId: target['id'] as String,
      targetLabel: target['label'] as String,
      keyframes: frames,
    );
  }

  /// The target at [position] of the recorded source, or null when no rider
  /// position is known (before the first keyframe cannot happen; after an
  /// `unknown` keyframe or across a gap that is too large it does).
  ///
  /// A visible span returns [TargetVisibility.visible]; an occluded span returns
  /// the last-known box as [TargetVisibility.coasting].
  TrackTargetState? at(Duration position) {
    final t = position.inMicroseconds / Duration.microsecondsPerSecond;
    if (t < _kfs.first.t) return null;
    // Last keyframe with time <= t.
    var lo = 0, hi = _kfs.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_kfs[mid].t <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final i = lo;
    final a = _kfs[i];
    switch (a.state) {
      case _KeyState.unknown:
        return null;
      case _KeyState.occluded:
        return _target(a.box!, TargetVisibility.coasting);
      case _KeyState.visible:
        break;
    }
    final b = i + 1 < _kfs.length ? _kfs[i + 1] : null;
    if (b == null || b.state != _KeyState.visible) {
      // Hold the last visible box until the next keyframe changes the state.
      return _target(a.box!, TargetVisibility.visible);
    }
    if (b.t - a.t > maxInterpolationGapS) {
      // Do not invent motion across a long unannotated gap.
      return t == a.t ? _target(a.box!, TargetVisibility.visible) : null;
    }
    final prev = i > 0 &&
            _kfs[i - 1].state == _KeyState.visible &&
            a.t - _kfs[i - 1].t <= maxInterpolationGapS
        ? _kfs[i - 1]
        : null;
    final next = i + 2 < _kfs.length &&
            _kfs[i + 2].state == _KeyState.visible &&
            _kfs[i + 2].t - b.t <= maxInterpolationGapS
        ? _kfs[i + 2]
        : null;
    return _target(_hermite(prev, a, b, next, t), TargetVisibility.visible);
  }

  TrackTargetState _target(NormBox box, TargetVisibility v) => TrackTargetState(
        id: targetId,
        label: targetLabel,
        box: box,
        visibility: v,
        provenance: TargetProvenance.demoAnnotation,
      );

  static NormBox _hermite(
      _Keyframe? p, _Keyframe a, _Keyframe b, _Keyframe? n, double t) {
    final dt = b.t - a.t;
    final u = (t - a.t) / dt;
    final u2 = u * u, u3 = u2 * u;
    final h00 = 2 * u3 - 3 * u2 + 1;
    final h10 = u3 - 2 * u2 + u;
    final h01 = -2 * u3 + 3 * u2;
    final h11 = u3 - u2;
    double ch(double pa, double pb, double? pp, double? pn) {
      final ma =
          (pp != null ? (pb - pp) / (b.t - p!.t) : (pb - pa) / dt) * _tension;
      final mb =
          (pn != null ? (pn - pa) / (n!.t - a.t) : (pb - pa) / dt) * _tension;
      return h00 * pa + h10 * dt * ma + h01 * pb + h11 * dt * mb;
    }

    final ab = a.box!, bb = b.box!;
    return NormBox(
      cx: ch(ab.cx, bb.cx, p?.box!.cx, n?.box!.cx),
      cy: ch(ab.cy, bb.cy, p?.box!.cy, n?.box!.cy),
      w: ch(ab.w, bb.w, p?.box!.w, n?.box!.w),
      h: ch(ab.h, bb.h, p?.box!.h, n?.box!.h),
    );
  }
}
