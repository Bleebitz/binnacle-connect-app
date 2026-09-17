import 'package:flutter/material.dart';

import '../theme/binnacle_theme.dart';

/// The brand wave-glow background used behind ambient/dashboard-style
/// screens — the splash screen, My Boat, account/settings, and empty/
/// loading states. Deliberately NOT used behind the Live camera view or
/// Library's dense grid: those screens make real media the dominant
/// background instead, per the product decision this widget's callers
/// follow (see each screen for the reasoning at its own call site).
///
/// This only ever wraps a screen's content — it does not manage layout —
/// so callers still own their own Scaffold/AppBar and just make them
/// transparent so the image shows through. See MyBoatScreen for the usual
/// pattern.
class BinnacleBackground extends StatelessWidget {
  final Widget child;

  /// A soft top/bottom scrim so text sitting directly over a bright swirl
  /// (e.g. an AppBar title) stays legible. On by default; screens whose
  /// content never overlaps the image's brighter regions can turn it off.
  final bool scrim;

  const BinnacleBackground({super.key, required this.child, this.scrim = true});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Solid base first: covers any edge the image doesn't reach on an
        // unusual aspect ratio, and is what actually shows while the image
        // decodes on a slower device.
        const ColoredBox(color: BinnacleColors.navyDeep),
        Image.asset(
          'assets/backgrounds/wave_glow.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
        if (scrim)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(
                      0x99081722), // BinnacleColors.navyDeep, ~60% — top app bar area
                  Colors.transparent,
                  Colors.transparent,
                  Color(0xB3081722), // ~70% — bottom nav / content footer area
                ],
                stops: [0.0, 0.22, 0.65, 1.0],
              ),
            ),
          ),
        child,
      ],
    );
  }
}
