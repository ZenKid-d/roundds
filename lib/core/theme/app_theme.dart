import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Тема приложения. Строится от текущего акцентного цвета (динамического из
/// обложки), на AMOLED-чёрном фоне, с геометрическим шрифтом (Poppins) и
/// сильно скруглёнными формами.
class AppTheme {
  static ThemeData build(Color accent) {
    final base = ThemeData.dark(useMaterial3: true);
    final text = GoogleFonts.poppinsTextTheme(base.textTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: accent,
        surface: AppColors.background,
        onPrimary: Colors.black,
      ),
      textTheme: text,
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        trackHeight: 4,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surface1,
        scrimColor: Colors.black54,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      cardTheme: CardThemeData(
        color: AppColors.surface1,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}
