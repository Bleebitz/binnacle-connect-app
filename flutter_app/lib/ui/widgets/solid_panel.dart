import 'package:flutter/material.dart';

import '../theme/binnacle_theme.dart';

/// A nearly-opaque navy panel for content that needs to stay legible over
/// [BinnacleBackground]'s wave artwork — Community's tab content, People's
/// rider list/input, session empty states, and the non-demo message. Inset
/// by [margin] so the wave stays visible around the edges, per the approved
/// design direction, rather than covering the whole screen.
///
/// Deliberately its own small widget instead of a change to
/// `BinnacleBackground` itself — that widget's default (transparent, wave
/// fully visible) stays exactly as every other screen already uses it.
class SolidPanel extends StatelessWidget {
  const SolidPanel({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(12, 8, 12, 12),
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsets margin;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: BinnacleColors.navy.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: BinnacleColors.offWhite.withValues(alpha: 0.08)),
        ),
        child: child,
      ),
    );
  }
}
