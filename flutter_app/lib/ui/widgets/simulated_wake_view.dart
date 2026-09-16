import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/binnacle_theme.dart';

/// Stand-in for the live camera feed when no Vision device is paired.
/// Canvas-drawn rather than a bundled photo/video, so the demo doesn't ship
/// with licensed footage and stays a few KB. Motion alone is enough to read
/// as "a feed" rather than a static placeholder — EptzVideoView still
/// stamps the honest SIMULATED badge over this, per the never-imply-measured
/// rule elsewhere in this app.
class SimulatedWakeView extends StatefulWidget {
  const SimulatedWakeView({super.key});

  @override
  State<SimulatedWakeView> createState() => _SimulatedWakeViewState();
}

class _SimulatedWakeViewState extends State<SimulatedWakeView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        painter: _WakeScenePainter(_c.value),
        size: Size.infinite,
      ),
    );
  }
}

class _WakeScenePainter extends CustomPainter {
  final double t;
  _WakeScenePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * 0.38;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, horizon),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF13324A), Color(0xFF1E4A63)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, horizon)),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, horizon, size.width, size.height - horizon),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F3244), Color(0xFF081A25)],
        ).createShader(Rect.fromLTWH(0, horizon, size.width, size.height - horizon)),
    );

    // Scrolling ripple lines give the water a sense of forward motion —
    // three bands at different speeds/opacities for a cheap parallax feel.
    final ripplePaint = Paint()
      ..color = BinnacleColors.tealBright.withValues(alpha: 0.10)
      ..strokeWidth = 1.4;
    for (var band = 0; band < 3; band++) {
      final speed = 1.0 + band * 0.6;
      final rowSpacing = 22.0 + band * 10;
      final phase = (t * speed * rowSpacing) % rowSpacing;
      for (double y = horizon + phase; y < size.height; y += rowSpacing) {
        final depth = (y - horizon) / (size.height - horizon);
        final wobble = math.sin((t * 2 * math.pi * speed) + y * 0.05) * 4 * depth;
        canvas.drawLine(
          Offset(0, y + wobble),
          Offset(size.width, y - wobble),
          ripplePaint..color = BinnacleColors.tealBright.withValues(alpha: 0.06 + 0.05 * depth),
        );
      }
    }

    // Wake V trailing from the bottom center, as if from the towboat this
    // camera is mounted on.
    final wakePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final origin = Offset(size.width / 2, size.height + 10);
    for (final side in [-1.0, 1.0]) {
      final path = Path()..moveTo(origin.dx, origin.dy);
      final end = Offset(origin.dx + side * size.width * 0.55, horizon + (size.height - horizon) * 0.15);
      final control = Offset(origin.dx + side * size.width * 0.18, size.height * 0.7);
      path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      canvas.drawPath(path, wakePaint);
    }

    // Sun glare near the horizon, subtly pulsing.
    final glareAlpha = 0.10 + 0.03 * math.sin(t * 2 * math.pi);
    canvas.drawCircle(
      Offset(size.width * 0.72, horizon - 4),
      size.width * 0.09,
      Paint()
        ..color = BinnacleColors.amber.withValues(alpha: glareAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    canvas.drawLine(
      Offset(0, horizon),
      Offset(size.width, horizon),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _WakeScenePainter oldDelegate) => oldDelegate.t != t;
}
