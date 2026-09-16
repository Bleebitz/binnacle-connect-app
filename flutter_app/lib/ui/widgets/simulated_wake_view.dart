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
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the platform's reduce-motion setting, and — just as
    // importantly — keep this perpetual animation from making
    // WidgetTester.pumpAndSettle() hang forever in tests, which also set
    // this flag (see test/widget_test.dart). A single static frame is a
    // fine fallback either way.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (warmth, night) = _timeOfDayFactors(DateTime.now());
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        painter: _WakeScenePainter(_c.value, warmth: warmth, night: night),
        size: Size.infinite,
      ),
    );
  }
}

/// Real time of day, not the animation clock — this is what makes the
/// tint context-aware rather than just another decorative cycle. Returns
/// (warmth, night): warmth peaks at dawn and dusk (a golden-hour glow),
/// night ramps in overnight and darkens/desaturates everything.
(double warmth, double night) _timeOfDayFactors(DateTime now) {
  final hour = now.hour + now.minute / 60.0;
  double bump(double center) => math.exp(-math.pow((hour - center) / 1.5, 2).toDouble());
  final warmth = (bump(6) + bump(18)).clamp(0.0, 1.0);
  final distFromMidnight = math.min((hour - 0).abs(), (hour - 24).abs());
  final night = (1 - distFromMidnight / 5).clamp(0.0, 1.0);
  return (warmth, night);
}

class _WakeScenePainter extends CustomPainter {
  final double t;
  final double warmth;
  final double night;
  _WakeScenePainter(this.t, {required this.warmth, required this.night});

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * 0.38;

    Color tod(Color cool, Color warm, Color nightColor) =>
        Color.lerp(Color.lerp(cool, warm, warmth), nightColor, night)!;

    final skyTop = tod(const Color(0xFF13324A), const Color(0xFF6B3A2E), const Color(0xFF060B14));
    final skyBottom = tod(const Color(0xFF1E4A63), const Color(0xFFB5602E), const Color(0xFF0A1420));
    final waterTop = tod(const Color(0xFF0F3244), const Color(0xFF4A2A22), const Color(0xFF050F17));
    final waterBottom = tod(const Color(0xFF081A25), const Color(0xFF1E120E), const Color(0xFF03080D));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, horizon),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [skyTop, skyBottom],
        ).createShader(Rect.fromLTWH(0, 0, size.width, horizon)),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, horizon, size.width, size.height - horizon),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [waterTop, waterBottom],
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

    // Sun glare near the horizon, subtly pulsing — brighter and warmer
    // during golden hour, all but gone at night.
    final glareAlpha = (0.10 + 0.03 * math.sin(t * 2 * math.pi) + warmth * 0.14) * (1 - night * 0.85);
    canvas.drawCircle(
      Offset(size.width * 0.72, horizon - 4),
      size.width * (0.09 + warmth * 0.02),
      Paint()
        ..color = Color.lerp(BinnacleColors.amber, const Color(0xFFFF7A3D), warmth)!.withValues(alpha: glareAlpha)
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
  bool shouldRepaint(covariant _WakeScenePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.warmth != warmth || oldDelegate.night != night;
}
