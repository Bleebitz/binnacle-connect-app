import 'package:flutter/material.dart';
import '../theme/binnacle_theme.dart';

/// Man-overboard alert surface. Per the corrected control channel design,
/// safety state is always-on and read-only from this app's perspective —
/// this widget only ever ACKNOWLEDGES an active alert, it never has a way
/// to suppress fall/MOB detection itself.
class MobAlertBanner extends StatelessWidget {
  final bool active;
  final String? lat;
  final String? lon;
  final double? headingDegrees;
  final VoidCallback onAcknowledge;

  const MobAlertBanner({
    super.key,
    required this.active,
    this.lat,
    this.lon,
    this.headingDegrees,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    // Align bottom-center rather than relying on a bare Positioned(bottom:0)
    // in the caller's Stack: that gives this widget's Column loose,
    // unbounded constraints, so its natural height can exceed the Stack's
    // clipped bounds and push the AnimatedSlide's hidden position (and the
    // Acknowledge button's hit-test rect) outside where it's actually
    // rendered. Align keeps geometry (and therefore hit-testing) consistent
    // with what's on screen regardless of content height.
    return Align(
      alignment: Alignment.bottomCenter,
      child: IgnorePointer(
        ignoring: !active,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 350),
          offset: active ? Offset.zero : const Offset(0, 1),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [BinnacleColors.orange.withValues(alpha: 0), BinnacleColors.orange.withValues(alpha: 0.94)],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('MAN OVERBOARD ALERT',
                      style: BinnacleTheme.mono(size: 13, color: Colors.white, weight: FontWeight.w700)),
                ]),
                const SizedBox(height: 10),
                if (headingDegrees != null)
                  Transform.rotate(
                    angle: headingDegrees! * 3.14159 / 180,
                    child: const Icon(Icons.navigation, color: Colors.white, size: 30),
                  ),
                if (lat != null && lon != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('POS $lat, $lon', style: BinnacleTheme.mono(size: 11, color: Colors.white)),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onAcknowledge,
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: BinnacleColors.orange),
                    child: const Text('Acknowledge — clip saved'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
