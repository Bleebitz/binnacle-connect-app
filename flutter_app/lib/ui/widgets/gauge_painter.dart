import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/binnacle_theme.dart';

/// 60 FPS-capable CustomPainter gauge, per the Flutter spec's rationale for
/// choosing Flutter (Skia/Impeller canvas rendering) over a WebView-based
/// approach. Draws a radial speed/telemetry gauge.
class GaugePainter extends CustomPainter {
  final double value;      // 0.0–1.0 normalized
  final double maxLabel;   // real-world max, for the numeric label
  final String unit;
  final Color accent;

  GaugePainter({
    required this.value,
    required this.maxLabel,
    required this.unit,
    this.accent = BinnacleColors.tealBright,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 6;

    final track = Paint()
      ..color = BinnacleColors.slateDim.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final fill = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    const startAngle = math.pi * 0.75;
    const sweepMax = math.pi * 1.5;

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepMax, false, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepMax * value.clamp(0.0, 1.0),
      false,
      fill,
    );

    final label = TextPainter(
      text: TextSpan(
        text: (value * maxLabel).toStringAsFixed(0),
        style: BinnacleTheme.mono(size: radius * 0.5, color: BinnacleColors.offWhite, weight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, center - Offset(label.width / 2, label.height / 2 + radius * 0.12));

    final unitLabel = TextPainter(
      text: TextSpan(text: unit, style: BinnacleTheme.mono(size: radius * 0.18)),
      textDirection: TextDirection.ltr,
    )..layout();
    unitLabel.paint(canvas, center - Offset(unitLabel.width / 2, -radius * 0.22));
  }

  @override
  bool shouldRepaint(covariant GaugePainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.accent != accent;
}

class TelemetryGauge extends StatelessWidget {
  final double value;
  final double maxLabel;
  final String unit;
  final double size;
  final Color? accent;

  const TelemetryGauge({
    super.key,
    required this.value,
    required this.maxLabel,
    required this.unit,
    this.size = 96,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: GaugePainter(value: value, maxLabel: maxLabel, unit: unit, accent: accent ?? BinnacleColors.tealBright),
      ),
    );
  }
}
