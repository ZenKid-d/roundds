import 'package:flutter/material.dart';

/// Палитра «тёмный премиум» на чистом AMOLED-чёрном.
class AppColors {
  static const background = Color(0xFF000000);
  static const surface1 = Color(0xFF0C0C0C);
  static const surface2 = Color(0xFF141414);
  static final white06 = Colors.white.withValues(alpha: 0.06);
  static final white45 = Colors.white.withValues(alpha: 0.45);
  static final white60 = Colors.white.withValues(alpha: 0.60);

  /// Акцент по умолчанию (пока нет обложки текущего трека).
  static const defaultAccent = Color(0xFFB388FF);

  // Цвета сервисов (используются и в SourceType).
  static const youtube = Color(0xFFFF0000);
  static const soundcloud = Color(0xFFFF5500);
  static const yandex = Color(0xFFFFCC00);
}
