import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/theme_settings.dart';

/// Обложка с плейсхолдером и скруглением. Если URL нет — рисуем градиент-заглушку.
class Artwork extends StatelessWidget {
  const Artwork(this.url, {super.key, this.size, this.radius, this.seed});

  final String? url;
  final double? size;

  /// Если не задан — берём радиус из настроек (AppShapes).
  final double? radius;

  /// Для стабильного цвета заглушки (например, uid трека).
  final String? seed;

  /// Превью YouTube (i.ytimg.com) — это кадр 4:3 с чёрными полосами сверху и
  /// снизу. Чтобы обложка выглядела квадратной без полос, слегка приближаем
  /// картинку по центру: полосы (~12.5% сверху/снизу) уходят за пределы кадра.
  static const _ytZoom = 1.34;

  @override
  Widget build(BuildContext context) {
    final r = radius ??
        Theme.of(context).extension<AppShapes>()?.radius ??
        16;
    final placeholder = _placeholder();
    final isYtThumb = url != null && url!.contains('i.ytimg.com');
    Widget child = (url == null || url!.isEmpty)
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder,
          );
    if (isYtThumb) {
      // Приближаем по центру — обрезаем чёрные полосы прямоугольного превью.
      child = Transform.scale(scale: _ytZoom, child: child);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _placeholder() {
    final h = (seed ?? url ?? 'x').hashCode;
    final c1 = HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.5, 0.45).toColor();
    final c2 =
        HSLColor.fromAHSL(1, ((h ~/ 7) % 360).toDouble(), 0.5, 0.3).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c1, c2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.music_note, color: AppColors.white45, size: 28),
    );
  }
}
