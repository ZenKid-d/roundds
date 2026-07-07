/// Recs v2.1 — настроение волны. Приблизительно, через теги Last.fm: теги
/// настроения подмешиваются в сиды генерации (tag.getTopTracks) и дают бонус в
/// скоринге кандидатам с совпадающими тегами. Работает при наличии ключа
/// Last.fm; без него влияние минимально (аудиоанализа на устройстве нет).
library;

enum WaveMood { any, energetic, chill, happy, sad, aggressive, romantic }

extension WaveMoodX on WaveMood {
  String get id => name;

  String get label => switch (this) {
        WaveMood.any => 'Любое',
        WaveMood.energetic => 'Бодрое',
        WaveMood.chill => 'Спокойное',
        WaveMood.happy => 'Весёлое',
        WaveMood.sad => 'Грустное',
        WaveMood.aggressive => 'Агрессивное',
        WaveMood.romantic => 'Романтичное',
      };

  /// Теги Last.fm настроения (lowercase). Пусто для [WaveMood.any].
  List<String> get tags => switch (this) {
        WaveMood.any => const [],
        WaveMood.energetic => const ['energetic', 'upbeat', 'party', 'dance'],
        WaveMood.chill => const [
            'chill',
            'chillout',
            'relaxing',
            'mellow',
            'ambient'
          ],
        WaveMood.happy => const ['happy', 'feel good', 'uplifting', 'summer'],
        WaveMood.sad => const ['sad', 'melancholy', 'melancholic', 'emotional'],
        WaveMood.aggressive => const [
            'aggressive',
            'angry',
            'heavy',
            'intense'
          ],
        WaveMood.romantic => const ['romantic', 'love songs', 'sensual'],
      };

  static WaveMood fromId(String? s) => WaveMood.values
      .firstWhere((e) => e.name == s, orElse: () => WaveMood.any);
}
