import 'package:flutter/material.dart';
import '../theme/binnacle_theme.dart';

/// Shared empty-state treatment: a softly glowing icon badge over a title
/// and a subtitle that says what makes the thing show up, not just "there's
/// nothing here." Every list/feed screen used bare centered text before this
/// (or, at best, a flat icon) — this is the one place to fix that for all
/// of them at once.
class BinnacleEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  const BinnacleEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent = BinnacleColors.tealBright,
    this.titleStyle,
    this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlowBadge(icon: icon, accent: accent),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: titleStyle ??
                  const TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontWeight: FontWeight.w700,
                      fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: subtitleStyle ??
                  const TextStyle(
                      color: BinnacleColors.slate, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// A slow, subtle breathing glow behind the icon — enough to feel alive
/// without being distracting on a screen that's otherwise just... empty.
class _GlowBadge extends StatefulWidget {
  final IconData icon;
  final Color accent;
  const _GlowBadge({required this.icon, required this.accent});

  @override
  State<_GlowBadge> createState() => _GlowBadgeState();
}

class _GlowBadgeState extends State<_GlowBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Every screen stays mounted under the root shell's Stack (see
    // main.dart), so a perpetual animation here runs even on screens the
    // user isn't looking at — and would hang WidgetTester.pumpAndSettle()
    // in every test if it didn't respect this, same as SimulatedWakeView
    // and the Library sheen.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.accent.withValues(alpha: 0.07 + t * 0.03),
            boxShadow: [
              BoxShadow(
                  color: widget.accent.withValues(alpha: 0.10 + t * 0.10),
                  blurRadius: 22 + t * 10),
            ],
          ),
          child: Icon(widget.icon,
              size: 30,
              color: widget.accent.withValues(alpha: 0.85 + t * 0.15)),
        );
      },
    );
  }
}
