import 'package:flutter/material.dart';

import '../theme/binnacle_theme.dart';
import '../widgets/binnacle_background.dart';

/// Shown at app launch while main.dart's _AppStartup waits for both a
/// minimum display floor and PairingService.restore() to complete — see
/// that class for why the wait exists at all (real Keychain/Keystore reads,
/// not fabricated delay). This screen owns only the brand entrance moment;
/// _AppStartup owns all timing/readiness decisions.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _wordmarkFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    // Mark fades and scales in first (from a slightly-shrunk 0.88x, the
    // classic "settling into place" premium-splash feel), then the
    // CONNECT wordmark fades in once the mark has mostly landed — a
    // staggered entrance reads as more deliberate than everything
    // animating in unison.
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
      ),
    );
    _wordmarkFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BinnacleBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: Image.asset(
                        'assets/brand/binnacle_logo.png',
                        width: 148,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FadeTransition(
                    opacity: _wordmarkFade,
                    child: Text(
                      'CONNECT',
                      style: BinnacleTheme.mono(
                        size: 13,
                        color: BinnacleColors.tealBright,
                        weight: FontWeight.w600,
                      ).copyWith(letterSpacing: 7),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
