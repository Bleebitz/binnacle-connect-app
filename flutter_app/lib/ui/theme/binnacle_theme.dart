import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Palette matches the retro-hero / technical-instrument hybrid established
// in the prior UX prototype — consumer surfaces skew warm/retro, the live
// capture view skews cold/instrument. See spotter-v5 prototype notes.
class BinnacleColors {
  static const navy = Color(0xFF0D2333);
  static const navyDeep = Color(0xFF081722);
  static const navyRaised = Color(0xFF12314A);
  static const teal = Color(0xFF2FA4A9);
  static const tealBright = Color(0xFF4FC7CC);
  static const orange = Color(0xFFFF6B35);
  static const amber = Color(0xFFF2C94C);
  static const offWhite = Color(0xFFEDF1F2);
  static const slate = Color(0xFF7C93A3);
  static const slateDim = Color(0xFF4A5F6D);
}

class BinnacleTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: BinnacleColors.navyDeep,
      colorScheme: base.colorScheme.copyWith(
        primary: BinnacleColors.tealBright,
        secondary: BinnacleColors.orange,
        surface: BinnacleColors.navy,
        error: BinnacleColors.orange,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        titleLarge: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: BinnacleColors.offWhite,
        ),
        titleMedium: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w600,
          color: BinnacleColors.offWhite,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BinnacleColors.tealBright
              : BinnacleColors.slate,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BinnacleColors.teal.withValues(alpha: 0.35)
              : BinnacleColors.navyRaised,
        ),
      ),
      cardColor: BinnacleColors.navy,
      dividerColor: BinnacleColors.offWhite.withValues(alpha: 0.09),
    );
  }

  static TextStyle mono({double size = 11, Color? color, FontWeight? weight}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        color: color ?? BinnacleColors.slate,
        fontWeight: weight ?? FontWeight.w500,
      );
}
