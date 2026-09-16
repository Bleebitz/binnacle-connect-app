import 'package:flutter/material.dart';
import '../theme/binnacle_theme.dart';
import '../../core/services/telemetry_socket.dart';

/// Broadcast-graphics-style telemetry, fused directly onto the video rather
/// than off to the side in small dials. This is the app's actual point of
/// difference from a generic social feed — real sensor data, not just UGC —
/// so it earns a more prominent, more "sports broadcast" treatment.
class TelemetryOverlay extends StatelessWidget {
  final TelemetrySocket telemetry;
  const TelemetryOverlay({super.key, required this.telemetry});

  @override
  Widget build(BuildContext context) {
    if (telemetry.history.isEmpty) return const Text('Telemetry unavailable');
    final speed = telemetry.latest.speedMph;
    final history = telemetry.history;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpeedReadout(speed: speed),
        const SizedBox(height: 6),
        SizedBox(
          width: 132,
          height: 28,
          child: CustomPaint(
            painter: _SparklinePainter(
              history.map((s) => s.speedMph).toList(),
              min: 10,
              max: 28,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeedReadout extends StatefulWidget {
  final double speed;
  const _SpeedReadout({required this.speed});

  @override
  State<_SpeedReadout> createState() => _SpeedReadoutState();
}

class _SpeedReadoutState extends State<_SpeedReadout> {
  late double _previous = widget.speed;

  @override
  void didUpdateWidget(covariant _SpeedReadout old) {
    super.didUpdateWidget(old);
    _previous = old.speed;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.speed),
      tween: Tween(begin: _previous, end: widget.speed),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      builder: (context, value, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [BinnacleColors.tealBright, BinnacleColors.offWhite],
            ).createShader(bounds),
            child: Text(
              value.toStringAsFixed(0),
              style: const TextStyle(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w700,
                fontSize: 34,
                height: 1,
                color: Colors.white,
                shadows: [
                  Shadow(color: BinnacleColors.tealBright, blurRadius: 18),
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('MPH', style: BinnacleTheme.mono(size: 11, color: BinnacleColors.slate, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Rolling speed trace, oldest sample on the left. A glowing dot rides the
/// current value at the trailing edge, and the area under the curve fills
/// with a fading gradient — the "broadcast lower-third" look this is going
/// for, not a plain line chart.
class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final double min;
  final double max;
  _SparklinePainter(this.values, {required this.min, required this.max});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    double normY(double v) {
      final t = ((v - min) / (max - min)).clamp(0.0, 1.0);
      return size.height - t * size.height;
    }

    final dx = size.width / (values.length - 1);
    final points = [
      for (var i = 0; i < values.length; i++) Offset(i * dx, normY(values[i]))
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
      line.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);

    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BinnacleColors.tealBright.withValues(alpha: 0.28), BinnacleColors.tealBright.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = BinnacleColors.tealBright.withValues(alpha: 0.85),
    );

    final tip = points.last;
    canvas.drawCircle(tip, 5, Paint()..color = BinnacleColors.tealBright.withValues(alpha: 0.25));
    canvas.drawCircle(tip, 2.5, Paint()..color = BinnacleColors.tealBright);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.values != values;
}

/// Proximity ring around the AI tracking reticle — tightens and brightens
/// as the rider gets closer, so the telemetry and the tracking indicator
/// read as one system instead of two unrelated widgets.
class ProximityReticle extends StatelessWidget {
  final double riderDistanceM;
  const ProximityReticle({super.key, required this.riderDistanceM});

  @override
  Widget build(BuildContext context) {
    final closeness = (1 - ((riderDistanceM - 4) / (15 - 4))).clamp(0.0, 1.0);
    final ringRadius = 26 - closeness * 8;
    final color = Color.lerp(BinnacleColors.slate, BinnacleColors.tealBright, closeness)!;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: ringRadius, end: ringRadius),
            duration: const Duration(milliseconds: 400),
            builder: (context, r, _) => Container(
              width: r * 2,
              height: r * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35 * closeness + 0.05), blurRadius: 14)],
              ),
            ),
          ),
          Icon(Icons.gps_fixed, color: color, size: 30),
        ],
      ),
    );
  }
}
