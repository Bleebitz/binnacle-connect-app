import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/services/camera_media_source.dart' show RiderBoxStyle;
import '../theme/binnacle_theme.dart';

/// Draws the rider marker over the video. Corner brackets rather than a solid
/// frame, so the rider stays readable in sunlight; the style says how much to
/// trust it (dashed and dim while coasting, teal once the operator locked it).
///
/// The [rect] is computed by the SAME FramingGeometry that positions the video
/// pixels, so the marker stays on the rider at any zoom and pan.
class RiderBoxPainter extends CustomPainter {
  final Rect rect;
  final RiderBoxStyle style;

  /// Keeps the tag below any HUD strip along the top of the screen.
  final double tagTopInset;
  const RiderBoxPainter(
      {required this.rect, required this.style, this.tagTopInset = 0});

  static Color colorFor(RiderBoxStyle style) => switch (style) {
        RiderBoxStyle.locked => BinnacleColors.tealBright,
        RiderBoxStyle.tracking => Colors.white,
        RiderBoxStyle.candidate => BinnacleColors.amber,
        RiderBoxStyle.coasting => BinnacleColors.amber.withValues(alpha: 0.65),
      };

  static String tagFor(RiderBoxStyle style) => switch (style) {
        RiderBoxStyle.locked => 'RIDER LOCKED',
        RiderBoxStyle.tracking => 'TRACKING',
        RiderBoxStyle.candidate => 'RIDER',
        RiderBoxStyle.coasting => 'COASTING',
      };

  @override
  void paint(Canvas canvas, Size size) {
    final color = colorFor(style);
    // A dark halo keeps the marker visible over bright water and spray.
    final halo = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = style == RiderBoxStyle.locked ? 3.5 : 2.5
      ..strokeCap = StrokeCap.round;
    final r = rect;
    if (style == RiderBoxStyle.coasting) {
      _dashed(canvas, r, halo, line);
    } else {
      final len = math.min(r.width, r.height) * 0.28 + 6;
      for (final p in [halo, line]) {
        _corner(canvas, r.topLeft, len, 1, 1, p);
        _corner(canvas, r.topRight, len, -1, 1, p);
        _corner(canvas, r.bottomLeft, len, 1, -1, p);
        _corner(canvas, r.bottomRight, len, -1, -1, p);
      }
    }
    final tp = TextPainter(
      text: TextSpan(
        text: tagFor(style),
        style: BinnacleTheme.mono(
            size: 10.5, color: color, weight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Above the box when there is room; otherwise (a tight zoom pushes the top of
    // the box off screen) inside the visible part, and never under the HUD strip.
    final minY = math.max(2.0, tagTopInset);
    final maxY = math.max(minY, size.height - tp.height - 6);
    final wantY = r.top - tp.height - 4;
    final pos = Offset(
      math.max(2.0, math.min(r.left, size.width - tp.width - 8)),
      wantY >= minY ? wantY : math.min(math.max(r.top + 6, minY), maxY),
    );
    canvas.drawRect(
        Rect.fromLTWH(pos.dx - 3, pos.dy - 1, tp.width + 6, tp.height + 2),
        Paint()..color = Colors.black.withValues(alpha: 0.6));
    tp.paint(canvas, pos);
  }

  void _corner(Canvas c, Offset o, double len, double sx, double sy, Paint p) {
    c.drawLine(o, Offset(o.dx + sx * len, o.dy), p);
    c.drawLine(o, Offset(o.dx, o.dy + sy * len), p);
  }

  void _dashed(Canvas canvas, Rect r, Paint halo, Paint line) {
    for (final p in [halo, line]) {
      final path = Path()..addRect(r);
      for (final m in path.computeMetrics()) {
        var d = 0.0;
        while (d < m.length) {
          canvas.drawPath(m.extractPath(d, math.min(d + 9, m.length)), p);
          d += 16;
        }
      }
    }
  }

  @override
  bool shouldRepaint(RiderBoxPainter old) =>
      old.rect != rect || old.style != style || old.tagTopInset != tagTopInset;
}
