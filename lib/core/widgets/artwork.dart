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
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final isYtThumb = url != null && url!.contains('i.ytimg.com');

    return LayoutBuilder(
      builder: (context, constraints) {
        // Декодируем картинку под реальный размер отображения (× DPR), а не в
        // натуральном разрешении: обложки бывают 1000×1000, а в гриде/списке
        // показываются мелко — так экономим память и убираем джанк при скролле.
        final w = size ??
            (constraints.maxWidth.isFinite ? constraints.maxWidth : null);
        final cacheW = (w != null && w > 0) ? (w * dpr).round() : null;

        CachedNetworkImage img(String u,
                {Widget Function(BuildContext, String, Object)? errorWidget}) =>
            CachedNetworkImage(
              imageUrl: u,
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: cacheW,
              maxWidthDiskCache: cacheW,
              placeholder: (_, __) => _placeholder(),
              errorWidget: errorWidget ?? (_, __, ___) => _placeholder(),
            );

        Widget child;
        if (url == null || url!.isEmpty) {
          child = _placeholder();
        } else if (isYtThumb && url!.contains('sddefault')) {
          // Если sddefault отсутствует — падаем на hqdefault, потом заглушка.
          child = img(url!,
              errorWidget: (_, __, ___) =>
                  img(url!.replaceAll('sddefault', 'hqdefault')));
        } else {
          child = img(url!);
        }
        if (isYtThumb) {
          // Приближаем по центру — обрезаем чёрные полосы превью.
          child = Transform.scale(scale: _ytZoom, child: child);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: SizedBox(width: size, height: size, child: child),
        );
      },
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
