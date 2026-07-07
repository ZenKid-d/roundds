/// Recs v2 — anti-repetition: раскладка отранжированных кандидатов в
/// последовательность волны с соблюдением правил из ТЗ (лечим болезнь v1):
///  - один артист не чаще, чем раз в [WaveConstraints.minArtistGap] позиций;
///  - не более [WaveConstraints.maxPerArtistSession] раз за сессию;
///  - трек в cooldown ([WaveConstraints.cooldownDays] дней) не попадает в волну;
///  - кросс-источниковый дедуп по ключу.
/// Чистое и тестируемое, без БД/сети.
library;

class WaveConstraints {
  const WaveConstraints({
    this.minArtistGap = 5,
    this.maxPerArtistSession = 3,
    this.cooldownDays = 7,
  });

  final int minArtistGap;
  final int maxPerArtistSession;
  final int cooldownDays;

  /// Режим «Любимое» — cooldown мягче, плотность артиста чуть выше.
  static const favorite =
      WaveConstraints(minArtistGap: 4, maxPerArtistSession: 4, cooldownDays: 3);

  static const balanced = WaveConstraints();
}

/// Раскладывает [ranked] (в порядке убывания score) в валидную
/// последовательность. Кандидаты, которые нельзя разместить без нарушения
/// правил, отбрасываются. Обобщён по типу элемента — работает и с треками, и с
/// тестовыми структурами.
class WaveSequencer {
  const WaveSequencer._();

  static List<T> arrange<T>(
    List<T> ranked, {
    required String Function(T) artistKeyOf,
    required String Function(T) dedupKeyOf,
    int? Function(T)? lastPlayedSecAgoOf,
    WaveConstraints constraints = WaveConstraints.balanced,
    List<String> recentArtists = const [],
    int limit = 50,
  }) {
    final out = <T>[];
    final usedDedup = <String>{};
    // Хвост уже проигранного этой сессией — учитывается и в gap, и в лимите.
    final placedArtists = <String>[...recentArtists];
    final sessionCount = <String, int>{};
    for (final a in recentArtists) {
      sessionCount[a] = (sessionCount[a] ?? 0) + 1;
    }
    final cooldownSec = constraints.cooldownDays * 86400;

    final pending = List<T>.from(ranked);
    while (out.length < limit) {
      var placedThisPass = false;
      var i = 0;
      while (i < pending.length) {
        if (out.length >= limit) break;
        final cand = pending[i];
        final dKey = dedupKeyOf(cand);

        // Дубликат (кросс-источник) — выбрасываем навсегда.
        if (usedDedup.contains(dKey)) {
          pending.removeAt(i);
          continue;
        }
        // Cooldown — трек звучал слишком недавно, выбрасываем.
        final ago = lastPlayedSecAgoOf?.call(cand);
        if (ago != null && ago >= 0 && ago < cooldownSec) {
          pending.removeAt(i);
          continue;
        }

        final aKey = artistKeyOf(cand);
        // Лимит артиста за сессию.
        if ((sessionCount[aKey] ?? 0) >= constraints.maxPerArtistSession) {
          i++;
          continue;
        }
        // Плотность: артист не ближе, чем minArtistGap позиций.
        if (_artistTooClose(placedArtists, aKey, constraints.minArtistGap)) {
          i++; // может стать валидным на следующем проходе, когда окно сдвинется
          continue;
        }

        out.add(cand);
        usedDedup.add(dKey);
        placedArtists.add(aKey);
        sessionCount[aKey] = (sessionCount[aKey] ?? 0) + 1;
        pending.removeAt(i);
        placedThisPass = true;
      }
      // Полный проход без размещения — оставшихся нельзя разложить по правилам.
      if (!placedThisPass) break;
    }
    return out;
  }

  /// Появлялся ли [aKey] в последних `gap−1` элементах [placed] (нарушение
  /// «раз в gap позиций»).
  static bool _artistTooClose(List<String> placed, String aKey, int gap) {
    final window = gap - 1;
    if (window <= 0) return false;
    final from = placed.length - window;
    for (var j = placed.length - 1; j >= 0 && j >= from; j--) {
      if (placed[j] == aKey) return true;
    }
    return false;
  }
}
