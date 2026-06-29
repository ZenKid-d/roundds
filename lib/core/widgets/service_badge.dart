import 'package:flutter/material.dart';

import '../../domain/models/source_type.dart';

/// Маленький круглый бейдж сервиса (накладывается на угол обложки).
class ServiceBadge extends StatelessWidget {
  const ServiceBadge(this.source, {super.key, this.size = 20});

  final SourceType source;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: source.color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      alignment: Alignment.center,
      child: _glyph(),
    );
  }

  Widget _glyph() {
    switch (source) {
      case SourceType.youtube:
        return Icon(Icons.ondemand_video,
            size: size * 0.6, color: source.onColor);
      case SourceType.soundcloud:
        return Icon(Icons.cloud, size: size * 0.6, color: source.onColor);
      case SourceType.yandex:
        return Text('Я',
            style: TextStyle(
              fontSize: size * 0.6,
              height: 1,
              fontWeight: FontWeight.w600,
              color: source.onColor,
            ));
    }
  }
}

/// Пилюля «через <Сервис>» для экрана плеера.
class ServicePill extends StatelessWidget {
  const ServicePill(this.source, {super.key});

  final SourceType source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ServiceBadge(source, size: 14),
          const SizedBox(width: 6),
          Text('через ${source.shortLabel}',
              style: TextStyle(
                  fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
        ],
      ),
    );
  }
}
