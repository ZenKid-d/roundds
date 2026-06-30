import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'theme_settings.dart';

/// Тема приложения. Строится от выбранных настроек внешнего вида: акцентный
/// цвет, фон-пресет (через AppColors), радиус скруглений и шрифт.
class AppTheme {
  static ThemeData build({
    required Color accent,
    required double radius,
    required bool systemFont,
  }) {
    final base = ThemeData.dark(useMaterial3: true);
    final text = systemFont
        ? base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white)
        : GoogleFonts.poppinsTextTheme(base.textTheme)
            .apply(bodyColor: Colors.white, displayColor: Colors.white);

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
      extensions: [AppShapes(radius)],
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        trackHeight: 4,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: AppColors.surface1,
        scrimColor: Colors.black54,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      cardTheme: CardThemeData(
        color: AppColors.surface1,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
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
