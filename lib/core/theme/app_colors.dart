import 'package:flutter/material.dart';

/// Палитра «тёмный премиум». Фон/поверхности изменяемы — их задаёт
/// выбранный фон-пресет (см. ThemeSettingsController.applyBackground).
class AppColors {
  static Color background = const Color(0xFF000000);
  static Color surface1 = const Color(0xFF0C0C0C);
  static Color surface2 = const Color(0xFF141414);

  static void applyBackground(Color bg, Color s1, Color s2) {
    background = bg;
    surface1 = s1;
    surface2 = s2;
  }

  static final white06 = Colors.white.withValues(alpha: 0.06);
  static final white45 = Colors.white.withValues(alpha: 0.45);
  static final white60 = Colors.white.withValues(alpha: 0.60);

  /// Акцент по умолчанию (пока нет обложки текущего трека).
  static const defaultAccent = Color(0xFFB388FF);

  /// Жёлтый «что-то не так» — акцент при ошибке (трек не играет и т.п.).
  static const warning = Color(0xFFFFD23F);

  // Цвета сервисов (используются и в SourceType).
  static const youtube = Color(0xFFFF0000);
  static const soundcloud = Color(0xFFFF5500);
  static const yandex = Color(0xFFFFCC00);
}
