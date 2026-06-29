import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Обложка с плейсхолдером и скруглением. Если URL нет — рисуем градиент-заглушку.
class Artwork extends StatelessWidget {
  const Artwork(this.url, {super.key, this.size, this.radius = 18, this.seed});

  final String? url;
  final double? size;
  final double radius;

  /// Для стабильного цвета заглушки (например, uid трека).
  final String? seed;

  @override
  Widget build(BuildContext context) {
    final placeholder = _placeholder();
    final child = (url == null || url!.isEmpty)
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
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
