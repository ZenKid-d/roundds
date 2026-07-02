import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../providers.dart';
import 'app_colors.dart';
import 'theme_settings.dart';

/// URL обложки текущего трека. Меняет значение ТОЛЬКО при смене трека
/// (Riverpod пропускает одинаковые значения), поэтому акцент не пересчитывается
/// на каждый тик позиции.
final currentArtworkProvider = Provider<String?>((ref) {
  return ref.watch(playbackProvider).current?.artworkUrl;
});

/// Итоговый акцент с учётом режима: динамический из обложки / пресет / свой.
final effectiveAccentProvider = Provider<Color>((ref) {
  final ts = ref.watch(themeSettingsProvider);
  switch (ts.accentMode) {
    case AccentMode.dynamic:
      return ref.watch(accentProvider).valueOrNull ?? AppColors.defaultAccent;
    case AccentMode.preset:
      return ts.presetColor;
    case AccentMode.custom:
      return Color(ts.customColor);
  }
});

/// Динамический акцент: первый достаточно насыщенный цвет обложки.
/// Если обложка серая/чёрно-белая (нет цветного оттенка) — акцент белый
/// (не выдумываем случайный оттенок для серого).
final accentProvider = FutureProvider<Color>((ref) async {
  final url = ref.watch(currentArtworkProvider);
  if (url == null || url.isEmpty) return AppColors.defaultAccent;
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      CachedNetworkImageProvider(url),
      size: const Size(120, 120),
      maximumColorCount: 16,
    );

    // Кандидаты по приоритету: яркие → доминирующий → все свотчи.
    final candidates = <Color>[
      if (palette.vibrantColor != null) palette.vibrantColor!.color,
      if (palette.lightVibrantColor != null) palette.lightVibrantColor!.color,
      if (palette.darkVibrantColor != null) palette.darkVibrantColor!.color,
      if (palette.dominantColor != null) palette.dominantColor!.color,
      ...palette.paletteColors.map((p) => p.color),
    ];

    // Берём первый с реальным оттенком (насыщенность выше порога).
    for (final c in candidates) {
      if (HSLColor.fromColor(c).saturation >= 0.22) return _ensureVivid(c);
    }
    // Обложка чёрно-белая — акцент белый.
    return Colors.white;
  } catch (_) {
    return AppColors.defaultAccent;
  }
});

/// Поднимает насыщенность/яркость уже цветного акцента, чтобы читался на чёрном.
Color _ensureVivid(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withSaturation((hsl.saturation + 0.15).clamp(0.5, 1.0))
      .withLightness(hsl.lightness.clamp(0.55, 0.75))
      .toColor();
}
