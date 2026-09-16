import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/binnacle_theme.dart';

/// Frosted-glass modal bottom sheet — a real backdrop blur over whatever
/// screen is underneath, rather than the flat opaque navy card every sheet
/// in this app used before. Used sparingly: sheets and the bottom nav are
/// the only two places this app blurs anything (see main.dart's
/// _RootShell) — depth as an occasional accent, not a house style slapped
/// on every surface.
Future<T?> showGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: isScrollControlled,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: BinnacleColors.navy.withValues(alpha: 0.72),
            border: Border(top: BorderSide(color: BinnacleColors.offWhite.withValues(alpha: 0.08))),
          ),
          child: SafeArea(top: false, child: builder(ctx)),
        ),
      ),
    ),
  );
}
