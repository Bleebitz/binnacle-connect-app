// Framing geometry and Track Follow, tested deterministically (no screenshots):
// one shared source-to-viewport mapping, the safe-zone follow, smoothing, seek
// snapping, crop bounds, and the view modes.

import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'package:binnacle_connect/core/models/rider_track.dart';
import 'package:binnacle_connect/core/services/demo_media.dart';
import 'package:binnacle_connect/core/services/track_framing.dart';
import 'package:flutter_test/flutter_test.dart';

const _src = Size(1920, 1080);
// The S25 Ultra console viewport (contain), the portrait 16:9 card (cover), and
// the reverse landscape orientation, which is the same size as landscape.
const _console = Size(2340, 1080);
const _card = Size(376, 211.5);
const _reverseConsole = Size(2340, 1080);

DemoRiderTrack _track() =>
    DemoRiderTrack.parse(File(DemoRiderTrack.assetPath).readAsStringSync());

class _Rig {
  final DemoZoom zoom = DemoZoom();
  final ValueNotifier<DemoViewMode> mode =
      ValueNotifier(DemoViewMode.trackFollow);
  final DemoRiderLock lock = DemoRiderLock();
  late final DemoFraming framing =
      DemoFraming(zoom: zoom, viewMode: mode, riderLock: lock);

  _Rig(Size viewport, FrameFit fit, {DemoRiderTrack? track}) {
    framing.attachTrack(track ?? _track());
    framing.setViewport(viewport, fit);
  }

  /// Plays [from]..[to] in real time steps, like the per-frame ticker.
  void play(double from, double to, {double dt = 1 / 60}) {
    for (var t = from; t <= to; t += dt) {
      framing.update(Duration(microseconds: (t * 1e6).round()), dt: dt);
    }
  }

  void seek(double t) =>
      framing.update(Duration(microseconds: (t * 1e6).round()),
          dt: 1 / 60, seeked: true);

  void dispose() {
    framing.dispose();
    zoom.dispose();
    mode.dispose();
    lock.dispose();
  }
}

void main() {
  group('source-to-viewport geometry (BoxFit)', () {
    test('cover: a wider view crops the source vertically', () {
      const g = FramingGeometry(
          source: _src,
          viewport: Size(2340, 1080),
          fit: FrameFit.cover,
          zoom: 1);
      expect(g.baseScale, closeTo(2340 / 1920, 1e-12));
      // The visible height is only 1080 / (1080 * 1.21875) of the source.
      expect(g.visibleFraction.width, closeTo(1.0, 1e-12));
      expect(g.visibleFraction.height, closeTo(1 / 1.21875, 1e-9));
    });

    test('cover: a taller view crops the source horizontally', () {
      const g = FramingGeometry(
          source: _src, viewport: Size(400, 400), fit: FrameFit.cover, zoom: 1);
      expect(g.baseScale, closeTo(400 / 1080, 1e-12));
      expect(g.visibleFraction.height, closeTo(1.0, 1e-12));
      expect(g.visibleFraction.width, closeTo(1080 / 1920, 1e-9));
    });

    test('contain: shows the whole frame, letterboxed on the long axis', () {
      const g = FramingGeometry(
          source: _src, viewport: _console, fit: FrameFit.contain, zoom: 1);
      expect(g.baseScale, closeTo(1.0, 1e-12));
      expect(g.visibleFraction.height, closeTo(1.0, 1e-12));
      expect(g.visibleFraction.width, greaterThan(1.0)); // bars left and right
    });

    test('the source centre is the viewport centre at 1x and zoomed', () {
      for (final z in [1.0, 2.0, 4.0]) {
        final g = FramingGeometry(
            source: _src, viewport: _console, fit: FrameFit.contain, zoom: z);
        final c = g.toScreen(const Offset(0.5, 0.5));
        expect(c.dx, closeTo(_console.width / 2, 1e-9));
        expect(c.dy, closeTo(_console.height / 2, 1e-9));
      }
    });

    test('toSource inverts toScreen at any zoom and focus', () {
      final g = FramingGeometry(
          source: _src,
          viewport: _console,
          fit: FrameFit.contain,
          zoom: 3,
          focus: const Offset(0.6, 0.55));
      for (final p in const [
        Offset(0.3, 0.4),
        Offset(0.66, 0.5),
        Offset(0.9, 0.9)
      ]) {
        final back = g.toSource(g.toScreen(p));
        expect(back.dx, closeTo(p.dx, 1e-12));
        expect(back.dy, closeTo(p.dy, 1e-12));
      }
    });

    test(
        'reverse landscape is identical to landscape (geometry depends only on size)',
        () {
      const a = FramingGeometry(
          source: _src,
          viewport: _console,
          fit: FrameFit.contain,
          zoom: 3,
          focus: Offset(0.6, 0.5));
      const b = FramingGeometry(
          source: _src,
          viewport: _reverseConsole,
          fit: FrameFit.contain,
          zoom: 3,
          focus: Offset(0.6, 0.5));
      const box = NormBox(cx: 0.62, cy: 0.5, w: 0.07, h: 0.3);
      expect(a.boxToScreen(box), b.boxToScreen(box));
      expect(a.matrix, b.matrix);
    });
  });

  group('the overlay uses the same transform as the video', () {
    test('the video matrix and the box agree on where the rider is', () {
      final t = _track();
      for (final z in [1.0, 2.0, 3.0, 4.0]) {
        for (final sec in [0.0, 30.0, 70.0, 110.0]) {
          final target = t.at(Duration(seconds: sec.toInt()))!;
          var g = FramingGeometry(
              source: _src, viewport: _console, fit: FrameFit.contain, zoom: z);
          g = g.withFocus(Offset(target.box.cx, target.box.cy));
          final m = g.matrix;
          // Where the matrix puts the rider's centre pixel...
          final viaMatrix = Offset(
            m.tx + target.box.cx * _src.width * m.scale,
            m.ty + target.box.cy * _src.height * m.scale,
          );
          // ...is where the overlay draws the box centre.
          final rect = g.boxToScreen(target.box);
          expect(rect.center.dx, closeTo(viaMatrix.dx, 1e-6),
              reason: 'z=$z t=$sec');
          expect(rect.center.dy, closeTo(viaMatrix.dy, 1e-6),
              reason: 'z=$z t=$sec');
          // And tapping the middle of that rectangle hits the rider in the source.
          final tapped = g.toSource(rect.center);
          expect(tapped.dx, closeTo(target.box.cx, 1e-9));
          expect(tapped.dy, closeTo(target.box.cy, 1e-9));
        }
      }
    });

    test('the box scales with the zoom (it is drawn in video space)', () {
      const box = NormBox(cx: 0.5, cy: 0.5, w: 0.1, h: 0.3);
      final g1 = const FramingGeometry(
          source: _src, viewport: _console, fit: FrameFit.contain, zoom: 1);
      final g3 = g1.withZoom(3);
      expect(g3.boxToScreen(box).width,
          closeTo(g1.boxToScreen(box).width * 3, 1e-9));
    });
  });

  group('crop bounds: no black or empty canvas', () {
    test('focus is clamped so the crop stays inside the video (left edge)', () {
      const g = FramingGeometry(
          source: _src, viewport: _console, fit: FrameFit.contain, zoom: 4);
      final f = g.clampFocus(const Offset(0.02, 0.5));
      final gg = g.withFocus(f);
      expect(gg.coversViewport, isTrue);
      // The crop cannot centre a rider at the very edge; it stops at the edge.
      expect(gg.toScreen(const Offset(0, 0.5)).dx, closeTo(0, 1e-6));
    });

    test('right edge', () {
      const g = FramingGeometry(
          source: _src, viewport: _console, fit: FrameFit.contain, zoom: 4);
      final gg = g.withFocus(const Offset(0.99, 0.5));
      expect(gg.coversViewport, isTrue);
      expect(
          gg.toScreen(const Offset(1, 0.5)).dx, closeTo(_console.width, 1e-6));
    });

    test('top and bottom boundaries', () {
      const g = FramingGeometry(
          source: _src, viewport: _console, fit: FrameFit.contain, zoom: 4);
      final top = g.withFocus(const Offset(0.5, 0.01));
      final bottom = g.withFocus(const Offset(0.5, 0.99));
      expect(top.coversViewport && bottom.coversViewport, isTrue);
      expect(top.toScreen(const Offset(0.5, 0)).dy, closeTo(0, 1e-6));
      expect(bottom.toScreen(const Offset(0.5, 1)).dy,
          closeTo(_console.height, 1e-6));
    });

    test('letterboxed at 1x the video is simply centred (nothing to pan)', () {
      const g = FramingGeometry(
          source: _src, viewport: _console, fit: FrameFit.contain, zoom: 1);
      expect(g.clampFocus(const Offset(0.9, 0.9)), const Offset(0.5, 0.5));
    });

    test(
        'over the whole pass, at every zoom and viewport, no empty canvas is exposed',
        () {
      for (final vp in [
        (_console, FrameFit.contain),
        (_card, FrameFit.cover)
      ]) {
        for (final z in [1.0, 1.5, 2.0, 3.0, 4.0]) {
          final rig = _Rig(vp.$1, vp.$2);
          rig.zoom.setZoom(z);
          for (var t = 0.0; t <= 125; t += 0.5) {
            rig.framing
                .update(Duration(milliseconds: (t * 1000).round()), dt: 0.5);
            expect(rig.framing.geometry!.coversViewport, isTrue,
                reason: 'viewport ${vp.$1} z=$z t=$t');
          }
          rig.dispose();
        }
      }
    });
  });

  group('Track Follow keeps the wakesurfer framed', () {
    /// Is the rider's centre inside the visible window (with a margin)?
    void expectRiderFramed(_Rig rig, double t, String why) {
      final target = rig.framing.target;
      if (target == null) return;
      final g = rig.framing.geometry!;
      final s = g.toScreen(Offset(target.box.cx, target.box.cy));
      final vp = g.viewport;
      expect(s.dx, inInclusiveRange(vp.width * 0.08, vp.width * 0.92),
          reason: '$why x at $t s: $s');
      expect(s.dy, inInclusiveRange(vp.height * 0.08, vp.height * 0.92),
          reason: '$why y at $t s: $s');
    }

    for (final z in [2.0, 3.0, 4.0]) {
      test(
          '${z.toInt()}x: the rider stays in the middle of the crop through the whole pass',
          () {
        final rig = _Rig(_console, FrameFit.contain);
        rig.zoom.setZoom(z);
        rig.seek(0);
        for (var t = 0.0; t <= 123.5; t += 1 / 60) {
          rig.framing
              .update(Duration(microseconds: (t * 1e6).round()), dt: 1 / 60);
          expectRiderFramed(rig, t, '${z.toInt()}x');
        }
        rig.dispose();
      });
    }

    test('the same holds in the portrait card', () {
      final rig = _Rig(_card, FrameFit.cover);
      rig.zoom.setZoom(3);
      rig.seek(0);
      for (var t = 0.0; t <= 123.5; t += 1 / 30) {
        rig.framing
            .update(Duration(microseconds: (t * 1e6).round()), dt: 1 / 30);
        expectRiderFramed(rig, t, 'card 3x');
      }
      rig.dispose();
    });

    test('1x produces no extra pan: the crop stays centred', () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.play(0, 60);
      expect(rig.framing.focus, const Offset(0.5, 0.5));
      rig.dispose();
    });

    test(
        'a rider on the far left / far right edge is framed as well as the source allows',
        () {
      // Synthetic track: rider hugging the left edge, then the right edge.
      final left = DemoRiderTrack.parse(_edgeTrack(0.03));
      final rig = _Rig(_console, FrameFit.contain, track: left);
      rig.zoom.setZoom(4);
      rig.seek(1);
      final g = rig.framing.geometry!;
      expect(g.coversViewport, isTrue,
          reason: 'no black strip at the left edge');
      final s = g.toScreen(
          Offset(rig.framing.target!.box.cx, rig.framing.target!.box.cy));
      expect(s.dx, greaterThanOrEqualTo(0));
      expect(s.dx, lessThan(_console.width * 0.25),
          reason: 'as close to centre as the source boundary permits');
      rig.dispose();

      final right = DemoRiderTrack.parse(_edgeTrack(0.97));
      final rig2 = _Rig(_console, FrameFit.contain, track: right);
      rig2.zoom.setZoom(4);
      rig2.seek(1);
      final g2 = rig2.framing.geometry!;
      expect(g2.coversViewport, isTrue);
      final s2 = g2.toScreen(
          Offset(rig2.framing.target!.box.cx, rig2.framing.target!.box.cy));
      expect(s2.dx, lessThanOrEqualTo(_console.width));
      expect(s2.dx, greaterThan(_console.width * 0.75));
      rig2.dispose();
    });

    test(
        'small drift inside the safe zone does not move the crop (no vibration)',
        () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.zoom.setZoom(3);
      rig.seek(20);
      final f0 = rig.framing.focus;
      // The rider moves a little (well inside the 12% safe zone of a 3x window).
      final g = rig.framing.geometry!;
      final small = g.visibleFraction.width * 0.05;
      final framer = TrackFollowFramer();
      framer.snap(g, NormBox(cx: f0.dx, cy: f0.dy, w: 0.05, h: 0.2));
      final after = framer.step(g.withFocus(framer.focus),
          NormBox(cx: f0.dx + small, cy: f0.dy, w: 0.05, h: 0.2), 0.5);
      expect(after.dx, closeTo(framer.focus.dx, 1e-12));
      expect((after.dx - f0.dx).abs(), lessThan(1e-9));
      rig.dispose();
    });

    test(
        'the rider box never leaves the view when it fits; tall boxes stay centred',
        () {
      const g = FramingGeometry(
          source: _src, viewport: _console, fit: FrameFit.contain, zoom: 2);
      final vis = g.visibleFraction; // 0.5 tall
      final framer = TrackFollowFramer();
      // A box that fits with room to spare: the crop must keep all of it visible.
      const fits = NormBox(cx: 0.5, cy: 0.5, w: 0.05, h: 0.30);
      for (var dy = 0.0; dy <= 0.2; dy += 0.02) {
        framer.reset(const Offset(0.5, 0.5));
        final f = framer.desiredFocus(g.withFocus(const Offset(0.5, 0.5)),
            NormBox(cx: 0.5, cy: 0.5 + dy, w: fits.w, h: fits.h));
        final view = g.withFocus(f);
        final r = view
            .boxToScreen(NormBox(cx: 0.5, cy: 0.5 + dy, w: fits.w, h: fits.h));
        expect(r.top, greaterThanOrEqualTo(-1),
            reason: 'top of the box, dy=$dy');
        expect(r.bottom, lessThanOrEqualTo(_console.height + 1),
            reason: 'bottom, dy=$dy');
      }
      // A box taller than the window cannot fit: the crop holds the upper body
      // (above the box centre) so the head stays and the lower legs are cropped.
      final tall = NormBox(cx: 0.5, cy: 0.52, w: 0.05, h: vis.height + 0.1);
      final f = framer.desiredFocus(g.withFocus(const Offset(0.5, 0.5)), tall);
      expect(f.dy, lessThan(0.52), reason: 'aims above the box centre');
      expect(f.dy, greaterThan(tall.top), reason: 'but inside the box');
      // A box that fits is simply centred on.
      const small = NormBox(cx: 0.5, cy: 0.52, w: 0.05, h: 0.2);
      expect(framer.anchor(g, small).dy, closeTo(0.52, 1e-9));
    });

    test('a large move pans smoothly: no jump, no overshoot, then settles', () {
      final g = const FramingGeometry(
          source: _src, viewport: _console, fit: FrameFit.contain, zoom: 3);
      final framer = TrackFollowFramer();
      framer.snap(g, const NormBox(cx: 0.3, cy: 0.5, w: 0.05, h: 0.2));
      const target = NormBox(cx: 0.6, cy: 0.5, w: 0.05, h: 0.2);
      var prev = framer.focus.dx;
      var maxStep = 0.0;
      for (var i = 0; i < 240; i++) {
        final f = framer.step(g.withFocus(framer.focus), target, 1 / 60);
        expect(f.dx, greaterThanOrEqualTo(prev - 1e-12), reason: 'monotone');
        expect(f.dx, lessThanOrEqualTo(target.cx + 1e-9),
            reason: 'no overshoot');
        maxStep = (f.dx - prev) > maxStep ? (f.dx - prev) : maxStep;
        prev = f.dx;
      }
      expect(maxStep, lessThan(0.03),
          reason: 'a per-frame step is a small fraction of the frame');
      // Settled with the rider inside the safe zone of the crop.
      final vis = g.visibleFraction.width;
      expect((framer.focus.dx - target.cx).abs(),
          lessThanOrEqualTo(vis * 0.12 + 1e-6));
    });

    test('the pan follows a moving rider without falling behind out of frame',
        () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.zoom.setZoom(4);
      rig.seek(0);
      var worst = 0.0;
      for (var t = 0.0; t <= 121; t += 1 / 60) {
        rig.framing
            .update(Duration(microseconds: (t * 1e6).round()), dt: 1 / 60);
        final target = rig.framing.target!;
        final g = rig.framing.geometry!;
        final s = g.toScreen(Offset(target.box.cx, target.box.cy));
        final off = (s.dx - _console.width / 2).abs() / _console.width;
        if (off > worst) worst = off;
      }
      expect(worst, lessThan(0.40),
          reason: 'rider never near the edge of the crop');
      rig.dispose();
    });

    test('after a deliberate seek the crop snaps to the rider immediately', () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.zoom.setZoom(3);
      rig.play(0, 3);
      final before = rig.framing.focus;
      rig.seek(100);
      final t = _track().at(const Duration(seconds: 100))!;
      final f = rig.framing.focus;
      expect((f.dx - t.box.cx).abs(), lessThan(1e-6),
          reason: 'no slow drift across the screen from the old position');
      expect(f, isNot(before));
      rig.dispose();
    });

    test('a jump in the position (a loop or an unflagged seek) also snaps', () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.zoom.setZoom(3);
      rig.play(0, 60);
      rig.framing.update(const Duration(seconds: 2), dt: 1 / 60); // loop wrap
      final t = _track().at(const Duration(seconds: 2))!;
      expect((rig.framing.focus.dx - t.box.cx).abs(), lessThan(1e-6));
      rig.dispose();
    });

    test(
        'changing zoom re-frames on the rider at once (pinch does not lose them)',
        () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.seek(20);
      for (final z in [1.5, 2.0, 3.0, 4.0, 2.0]) {
        rig.zoom.setZoom(z);
        rig.framing.update(const Duration(seconds: 20), dt: 1 / 60);
        final s = rig.framing.geometry!.toScreen(
            Offset(rig.framing.target!.box.cx, rig.framing.target!.box.cy));
        expect(
            (s.dx - _console.width / 2).abs(), lessThan(_console.width * 0.15));
      }
      rig.dispose();
    });

    test(
        'with no target known the crop holds instead of lurching to the centre',
        () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.zoom.setZoom(3);
      rig.seek(122);
      final held = rig.framing.focus;
      rig.framing.update(const Duration(milliseconds: 129700), dt: 1 / 60);
      expect(rig.framing.target, isNull);
      expect(rig.framing.focus, held);
      rig.dispose();
    });
  });

  group('view modes', () {
    test('RAW: centre framing, no rider box, no follow', () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.zoom.setZoom(3);
      rig.mode.value = DemoViewMode.raw;
      rig.seek(20);
      expect(rig.framing.target, isNull);
      expect(rig.framing.focus, const Offset(0.5, 0.5));
      rig.play(20, 60);
      expect(rig.framing.focus, const Offset(0.5, 0.5));
      rig.dispose();
    });

    test('MANUAL stops the automatic follow and keeps the rider box', () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.zoom.setZoom(3);
      rig.seek(20);
      rig.mode.value = DemoViewMode.manual;
      rig.seek(20);
      final held = rig.framing.focus;
      rig.play(20, 80);
      expect(rig.framing.focus, held,
          reason: 'the rider moved; the crop did not');
      expect(rig.framing.target, isNotNull, reason: 'the box is still shown');
      rig.dispose();
    });

    test('MANUAL drag pans the crop and is clamped to the video', () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.zoom.setZoom(3);
      rig.seek(20);
      rig.mode.value = DemoViewMode.manual;
      rig.seek(20);
      final start = rig.framing.focus;
      rig.framing.panManual(const Offset(-300, 0)); // drag left => look right
      expect(rig.framing.focus.dx, greaterThan(start.dx));
      rig.framing.panManual(const Offset(-99999, -99999));
      expect(rig.framing.geometry!.coversViewport, isTrue);
      rig.dispose();
    });

    test('panManual does nothing outside MANUAL', () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.zoom.setZoom(3);
      rig.seek(20);
      final f = rig.framing.focus;
      rig.framing.panManual(const Offset(-300, 0));
      expect(rig.framing.focus, f);
      rig.dispose();
    });

    test(
        'switching back from MANUAL reacquires the rider and re-frames on them',
        () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.zoom.setZoom(3);
      rig.seek(20);
      rig.mode.value = DemoViewMode.manual;
      rig.seek(20);
      rig.play(20, 70); // the rider moves far away while manual
      rig.mode.value = DemoViewMode.trackFollow;
      rig.framing.update(const Duration(seconds: 70), dt: 1 / 60);
      final t = _track().at(const Duration(seconds: 70))!;
      expect((rig.framing.focus.dx - t.box.cx).abs(), lessThan(1e-6));
      rig.dispose();
    });

    test('manual pan never overwrites the spatial rider track itself', () {
      final rig = _Rig(_console, FrameFit.contain);
      rig.zoom.setZoom(3);
      rig.mode.value = DemoViewMode.manual;
      rig.seek(20);
      final before = _track().at(const Duration(seconds: 20))!.box;
      rig.framing.panManual(const Offset(400, 100));
      expect(rig.framing.target!.box, before);
      rig.dispose();
    });
  });

  group('playback clock (extrapolates the player, never replaces it)', () {
    test('extrapolates between polls and adopts a seek at once', () {
      var now = Duration.zero;
      final c = DemoPlaybackClock(now: () => now);
      c.duration = const Duration(seconds: 130);
      expect(c.anchor(const Duration(seconds: 10)), isTrue,
          reason: 'first report from zero is a jump');
      now = const Duration(milliseconds: 60);
      expect(c.now, const Duration(milliseconds: 10060));
      // The next poll agrees: ordinary progress, not a jump.
      expect(c.anchor(const Duration(milliseconds: 10100)), isFalse);
      // The player reports a seek: adopted immediately.
      expect(c.anchor(const Duration(seconds: 90)), isTrue);
      expect(c.now, const Duration(seconds: 90));
    });

    test('a paused player is not extrapolated; the end is clamped', () {
      var now = Duration.zero;
      final c = DemoPlaybackClock(now: () => now);
      c.duration = const Duration(seconds: 130);
      c.anchor(const Duration(seconds: 50), playing: false);
      now = const Duration(seconds: 5);
      expect(c.now, const Duration(seconds: 50));
      c.anchor(const Duration(seconds: 129), playing: true);
      now = const Duration(seconds: 20);
      expect(c.now, const Duration(seconds: 130));
    });
  });
}

/// A two-keyframe synthetic track with the rider at [cx] the whole time.
String _edgeTrack(double cx) => '''
{"schema":"binnacle.demo_rider_track","version":1,"provenance":"test",
 "source":{"asset":"assets/demo/gopro_dev_footage.mp4",
  "sha256":"6815ded40dd19e8e4a0cf1db2c30b7eb9e04585029bc64d935c5c76ffdf33f8f",
  "width":1920,"height":1080,"durationS":130.0},
 "coordinateSystem":"normalized","maxInterpolationGapS":5.0,
 "targets":[{"id":"rider","label":"RIDER","keyframes":[
  {"t":0,"state":"visible","cx":$cx,"cy":0.5,"w":0.05,"h":0.25},
  {"t":2,"state":"visible","cx":$cx,"cy":0.5,"w":0.05,"h":0.25}]}]}
''';
