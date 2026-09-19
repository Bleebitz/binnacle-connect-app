// Framing for the recorded Demo camera: ONE geometry that the video pixels, the
// rider box overlay and tap hit-testing all share, plus the Track Follow
// controller that decides where the crop should look.
//
// Nothing here is Core or Jetson behaviour. It is the local Demo presentation of
// a pre-authored spatial rider track (see rider_track.dart).

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';

import '../models/rider_track.dart';
import 'demo_media.dart';

/// How the source frame fills its viewport at 1x. Mirrors [BoxFit.cover] and
/// [BoxFit.contain], the only two the Live screen uses.
enum FrameFit { cover, contain }

/// The single source-to-viewport mapping.
///
/// A point in normalised source coordinates `p` maps to the screen as
///
///     screen = viewport/2 + (p * sourceSize - focus * sourceSize) * scale
///
/// where `scale = baseScale * zoom` and `baseScale` is the BoxFit scale. The
/// video widget applies exactly this as its matrix, the overlay draws with
/// [toScreen], and taps are resolved with [toSource], so pixels, box and hit
/// area cannot disagree.
@immutable
class FramingGeometry {
  final Size source;
  final Size viewport;
  final FrameFit fit;
  final double zoom;

  /// The normalised source point shown at the centre of the viewport. Always
  /// kept inside the range that leaves no empty canvas ([clampFocus]).
  final Offset focus;

  const FramingGeometry({
    required this.source,
    required this.viewport,
    required this.fit,
    required this.zoom,
    this.focus = const Offset(0.5, 0.5),
  });

  /// Scale at zoom 1: source pixels to viewport pixels.
  double get baseScale {
    final sx = viewport.width / source.width;
    final sy = viewport.height / source.height;
    return fit == FrameFit.cover ? math.max(sx, sy) : math.min(sx, sy);
  }

  /// Total scale: source pixels to viewport pixels.
  double get scale => baseScale * zoom;

  /// The part of the source (normalised) that is visible: its width and height
  /// as fractions of the source. Larger than 1 only when the video is
  /// letterboxed at low zoom.
  Size get visibleFraction => Size(
        viewport.width / (source.width * scale),
        viewport.height / (source.height * scale),
      );

  /// [f] moved to the nearest focus that exposes no empty canvas. On an axis
  /// where the scaled video is smaller than the viewport (letterbox) the video
  /// is simply centred.
  Offset clampFocus(Offset f) {
    final v = visibleFraction;
    double axis(double value, double visible) {
      if (visible >= 1) return 0.5;
      final half = visible / 2;
      return value.clamp(half, 1 - half).toDouble();
    }

    return Offset(axis(f.dx, v.width), axis(f.dy, v.height));
  }

  FramingGeometry withFocus(Offset f) => FramingGeometry(
      source: source,
      viewport: viewport,
      fit: fit,
      zoom: zoom,
      focus: clampFocus(f));

  FramingGeometry withZoom(double z) => FramingGeometry(
      source: source, viewport: viewport, fit: fit, zoom: z, focus: focus);

  /// Where a normalised source point lands on the screen.
  Offset toScreen(Offset p) => Offset(
        viewport.width / 2 + (p.dx - focus.dx) * source.width * scale,
        viewport.height / 2 + (p.dy - focus.dy) * source.height * scale,
      );

  /// The normalised source point under a screen position.
  Offset toSource(Offset screen) => Offset(
        focus.dx + (screen.dx - viewport.width / 2) / (source.width * scale),
        focus.dy + (screen.dy - viewport.height / 2) / (source.height * scale),
      );

  /// A normalised box as a screen rectangle.
  Rect boxToScreen(NormBox b) => Rect.fromPoints(
        toScreen(Offset(b.left, b.top)),
        toScreen(Offset(b.right, b.bottom)),
      );

  /// Translation and scale that draw the full-size source at its screen place:
  /// `matrix = translate(tx, ty) * scale(s)` about the top-left corner.
  ({double tx, double ty, double scale}) get matrix => (
        tx: viewport.width / 2 - focus.dx * source.width * scale,
        ty: viewport.height / 2 - focus.dy * source.height * scale,
        scale: scale,
      );

  /// True when the visible area lies entirely inside the source (no black
  /// strips), on every axis where that is possible.
  bool get coversViewport {
    final v = visibleFraction;
    const eps = 1e-6;
    bool ok(double visible, double f) =>
        visible >= 1 - eps ||
        (f - visible / 2 >= -eps && f + visible / 2 <= 1 + eps);
    return ok(v.width, focus.dx) && ok(v.height, focus.dy);
  }
}

/// Track Follow: where should the crop look so the rider stays framed like a
/// camera operator would frame them?
///
///  * A CENTRAL SAFE ZONE (a fraction of the visible window) lets the rider drift
///    without moving the crop, so it does not vibrate.
///  * Outside it the crop pans just enough to hold the rider at the edge of that
///    zone, then eases toward it with an exponential smoothing so the pan has no
///    jumps, no overshoot and does not accumulate drift.
///  * The focus is clamped to the source so no empty canvas is ever exposed.
///  * After a deliberate seek (or loop) [snap] jumps straight to the right place
///    instead of panning across from the old one.
class TrackFollowFramer {
  /// Half-size of the safe zone as a fraction of the visible window.
  final double safeHalfX;
  final double safeHalfY;

  /// Smoothing time constant in seconds. Smaller follows tighter.
  final double smoothingS;

  Offset _focus = const Offset(0.5, 0.5);
  Offset get focus => _focus;

  TrackFollowFramer({
    this.safeHalfX = 0.12,
    this.safeHalfY = 0.14,
    this.smoothingS = 0.22,
  });

  /// The normalised point the crop should aim at for [target].
  ///
  /// Horizontally it is the box centre. Vertically it is the box centre while the
  /// whole box fits the window, and slides up toward the upper body (head and
  /// torso, at about 32% of the box height) as the box outgrows the window at tight
  /// zoom, so the head is kept and the lower legs are what get cropped.
  Offset anchor(FramingGeometry geometry, NormBox target) {
    final visH = geometry.visibleFraction.height;
    final k = ((target.h / visH - 0.8) / 0.4).clamp(0.0, 1.0);
    final fraction = 0.5 - 0.18 * k;
    return Offset(target.cx, target.top + fraction * target.h);
  }

  /// The focus the safe-zone rule wants for [target] given the current
  /// [geometry] (whose own focus is the current crop), before smoothing.
  ///
  /// The safe zone is a fraction of the visible window, but never larger than the
  /// room the rider's BOX leaves inside that window: if the box fits, it is never
  /// allowed to leave the view; if it does not fit (tight zoom on a tall rider),
  /// the crop holds the upper-body anchor. So the rider's head and board are not
  /// cut off while a smaller drift is still tolerated.
  Offset desiredFocus(FramingGeometry geometry, NormBox target) {
    final vis = geometry.visibleFraction;
    final cur = geometry.focus;
    final a = anchor(geometry, target);
    double axis(double c, double f, double visible, double safe, double box) {
      final room = math.max(0.0, (visible - box) / 2 - visible * 0.03);
      final allow = math.min(visible * safe, room);
      final d = c - f;
      if (d.abs() <= allow) return f;
      return c - allow * d.sign;
    }

    return geometry.clampFocus(Offset(
      axis(a.dx, cur.dx, vis.width, safeHalfX, target.w),
      axis(a.dy, cur.dy, vis.height, safeHalfY, target.h),
    ));
  }

  /// Advances the crop toward the rider by [dt] seconds. [geometry] must carry
  /// this framer's current focus. Returns the new (clamped) focus.
  Offset step(FramingGeometry geometry, NormBox target, double dt) {
    final want = desiredFocus(geometry, target);
    final k = 1 - math.exp(-dt / smoothingS);
    _focus = geometry.clampFocus(Offset(
      _focus.dx + (want.dx - _focus.dx) * k,
      _focus.dy + (want.dy - _focus.dy) * k,
    ));
    return _focus;
  }

  /// Jump straight to the framing for [target] (after a seek, a loop, a zoom
  /// change from 1x, or switching back to Track Follow).
  Offset snap(FramingGeometry geometry, NormBox target) {
    _focus = geometry.clampFocus(anchor(geometry, target));
    return _focus;
  }

  void reset([Offset focus = const Offset(0.5, 0.5)]) => _focus = focus;
}

/// The Demo view modes' framing behaviour.
///
///  * RAW: the uncontrolled camera view. Centre-framed, no rider overlay, no
///    follow. Digital zoom, if used, is centre zoom and is not Track Follow.
///  * TRACK FOLLOW: the crop follows the annotated rider.
///  * MANUAL: the operator owns the framing (pinch zoom + drag pan). The rider
///    box is still shown so they can see the rider, but nothing follows it.
///
/// Mode and zoom are presentation state of the Demo feed. They are never sent to
/// a Core.
class DemoFraming extends ChangeNotifier {
  final DemoZoom zoom;
  final ValueNotifier<DemoViewMode> viewMode;
  final DemoRiderLock riderLock;
  final TrackFollowFramer framer;

  DemoRiderTrack? _track;
  Size _viewport = Size.zero;
  FrameFit _fit = FrameFit.cover;
  Size _source = const Size(1920, 1080);

  Offset _focus = const Offset(0.5, 0.5);
  Offset _manualFocus = const Offset(0.5, 0.5);
  TrackTargetState? _target;
  Duration? _lastPosition;
  double _lastZoom = DemoZoom.min;
  DemoViewMode _lastMode = DemoViewMode.trackFollow;
  bool _needsSnap = true;

  DemoFraming({
    required this.zoom,
    required this.viewMode,
    required this.riderLock,
    TrackFollowFramer? framer,
  }) : framer = framer ?? TrackFollowFramer() {
    zoom.addListener(_onInputChanged);
    viewMode.addListener(_onInputChanged);
    riderLock.addListener(notifyListeners);
  }

  DemoRiderTrack? get track => _track;
  bool get hasTrack => _track != null;

  /// The current annotated target, or null when none is known (before the track
  /// loads, in RAW, or where the annotation has no rider position).
  TrackTargetState? get target => _target;

  /// Current focus of the crop (normalised source coordinates).
  Offset get focus => _focus;

  DemoViewMode get mode => viewMode.value;

  void attachTrack(DemoRiderTrack? track) {
    _track = track;
    if (track != null) {
      _source =
          Size(track.sourceWidth.toDouble(), track.sourceHeight.toDouble());
    }
    _needsSnap = true;
    notifyListeners();
  }

  /// Called by the video view whenever its layout changes.
  void setViewport(Size viewport, FrameFit fit) {
    if (viewport == _viewport && fit == _fit) return;
    _viewport = viewport;
    _fit = fit;
    _needsSnap = true;
    notifyListeners();
  }

  /// The geometry for the current frame, or null before the first layout.
  FramingGeometry? get geometry {
    if (_viewport.isEmpty) return null;
    return FramingGeometry(
      source: _source,
      viewport: _viewport,
      fit: _fit,
      zoom: zoom.value,
      focus: _focus,
    ).withFocus(_focus);
  }

  void _onInputChanged() {
    // A zoom or mode change re-frames immediately; smoothing applies to the
    // rider's movement, not to the operator's own action.
    _needsSnap = true;
    notifyListeners();
  }

  /// Advances to [position] (the SAME Demo playback position the video, Track
  /// state, Snapshot, Highlight and timeline use, extrapolated between player
  /// polls by DemoPlaybackClock) by [dt] seconds of wall time.
  ///
  /// [seeked] is true when the position jumped (a timeline seek or a loop):
  /// the target and the crop are re-initialised at once.
  void update(Duration position, {double dt = 1 / 60, bool seeked = false}) {
    final track = _track;
    final mode = viewMode.value;
    final prev = _target;

    final raw = track?.at(position);
    _target = (mode == DemoViewMode.raw) ? null : raw;

    final g0 = geometry;
    if (g0 == null) {
      _lastPosition = position;
      return;
    }

    var snap = seeked || _needsSnap;
    final last = _lastPosition;
    if (last != null &&
        (position - last).abs() > const Duration(milliseconds: 750)) {
      snap = true;
    }
    if (mode != _lastMode) {
      if (mode == DemoViewMode.manual) _manualFocus = _focus;
      snap = true;
    }
    if (zoom.value != _lastZoom) snap = true;
    _lastMode = mode;
    _lastZoom = zoom.value;
    _needsSnap = false;
    _lastPosition = position;

    Offset next = _focus;
    switch (mode) {
      case DemoViewMode.raw:
        next = const Offset(0.5, 0.5);
        framer.reset(next);
      case DemoViewMode.manual:
        next = g0.clampFocus(_manualFocus);
        _manualFocus = next;
        framer.reset(next);
      case DemoViewMode.trackFollow:
        final t = _target;
        if (t == null) {
          // No rider position known: hold the framing (do not lurch to centre).
          next = g0.clampFocus(_focus);
          framer.reset(next);
        } else {
          // At 1x the whole frame is visible, so clampFocus keeps the crop
          // centred and there is nothing to follow; the box still marks the rider.
          framer.reset(_focus);
          next = snap ? framer.snap(g0, t.box) : framer.step(g0, t.box, dt);
        }
    }

    final changed = (next - _focus).distanceSquared > 1e-12 ||
        prev?.box != _target?.box ||
        prev?.visibility != _target?.visibility;
    _focus = next;
    if (changed) notifyListeners();
  }

  /// MANUAL only: pan by a screen-space drag of [delta] pixels.
  void panManual(Offset delta) {
    final g = geometry;
    if (g == null || viewMode.value != DemoViewMode.manual) return;
    _manualFocus = g.clampFocus(Offset(
      _focus.dx - delta.dx / (g.source.width * g.scale),
      _focus.dy - delta.dy / (g.source.height * g.scale),
    ));
    _focus = _manualFocus;
    notifyListeners();
  }

  @override
  void dispose() {
    zoom.removeListener(_onInputChanged);
    viewMode.removeListener(_onInputChanged);
    riderLock.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Extrapolates the video player's position between its polls.
///
/// This is NOT a second clock. The player's reported position is the truth: each
/// report re-anchors this object, and a report that disagrees with the
/// extrapolation by more than [resyncThreshold] (a seek, a loop, a stall) makes
/// it adopt the player's value at once. It exists only because the player
/// reports its position a few times a second while the framing and rider box
/// are drawn every frame, and drawing at the poll rate would visibly step.
class DemoPlaybackClock {
  static const resyncThreshold = Duration(milliseconds: 400);

  final Duration Function() _now;
  Duration _anchor = Duration.zero;
  Duration _anchoredAt = Duration.zero;
  bool _playing = false;
  Duration? _duration;

  DemoPlaybackClock({Duration Function()? now}) : _now = now ?? _monotonic;

  static final Stopwatch _sw = Stopwatch()..start();
  static Duration _monotonic() => _sw.elapsed;

  set duration(Duration? d) => _duration = d;

  /// The player reported [position]. Returns true when this was a jump rather
  /// than ordinary progress.
  bool anchor(Duration position, {bool playing = true}) {
    final estimated = now;
    final jumped = (position - estimated).abs() > resyncThreshold;
    _anchor = position;
    _anchoredAt = _now();
    _playing = playing;
    return jumped;
  }

  /// The best estimate of the player's position right now.
  Duration get now {
    if (!_playing) return _anchor;
    var p = _anchor + (_now() - _anchoredAt);
    final d = _duration;
    if (d != null && p > d) p = d;
    return p;
  }
}
