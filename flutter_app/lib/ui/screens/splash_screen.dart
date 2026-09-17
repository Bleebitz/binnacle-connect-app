import 'package:flutter/material.dart';

import '../theme/binnacle_theme.dart';
import '../widgets/binnacle_background.dart';

/// Shown for a short, fixed window at app launch while main.dart's
/// _AppStartup awaits PairingService.restore() — see that class for why
/// the wait exists at all (real Keychain/Keystore reads, not fabricated
/// delay). This screen itself has no logic; it is purely the brand moment
/// the wave-glow background is strongest for.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BinnacleBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'BINNACLE',
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w700,
                  fontSize: 28,
                  letterSpacing: 6,
                  color: BinnacleColors.offWhite,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'CONNECT',
                style: BinnacleTheme.mono(
                        size: 12,
                        color: BinnacleColors.tealBright,
                        weight: FontWeight.w600)
                    .copyWith(letterSpacing: 6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
