import 'package:flutter/material.dart';

/// Источники музыки, поддерживаемые приложением.
/// Spotify и VK сознательно исключены (см. план): Spotify требует обхода DRM,
/// VK не выбран. Всё воспроизведение происходит внутри нашего плеера.
enum SourceType {
  youtube,
  soundcloud,
  yandex,
}

extension SourceTypeX on SourceType {
  String get label => switch (this) {
        SourceType.youtube => 'YouTube Music',
        SourceType.soundcloud => 'SoundCloud',
        SourceType.yandex => 'Яндекс Музыка',
      };

  /// Короткая подпись для бейджа.
  String get shortLabel => switch (this) {
        SourceType.youtube => 'YT Music',
        SourceType.soundcloud => 'SoundCloud',
        SourceType.yandex => 'Яндекс',
      };

  Color get color => switch (this) {
        SourceType.youtube => const Color(0xFFFF0000),
        SourceType.soundcloud => const Color(0xFFFF5500),
        SourceType.yandex => const Color(0xFFFFCC00),
      };

  /// Цвет текста поверх [color] (жёлтый Яндекса требует тёмного текста).
  Color get onColor =>
      this == SourceType.yandex ? const Color(0xFF3A2E00) : Colors.white;

  String get id => name;

  static SourceType fromId(String id) =>
      SourceType.values.firstWhere((e) => e.name == id,
          orElse: () => SourceType.youtube);
}
