/// Recs v2 — поточечный скоринг кандидата по формуле ТЗ:
///
///   score(t) = w_sim·sim(t, profile) + w_nov·novelty(t) + w_pop·popularity(t)
///            − w_rep·repetition_penalty(t) − w_neg·negative_affinity(t)
///
/// Чистое и тестируемое; веса вынесены в [ScoreWeights] (пресеты характера).
/// Жёсткие правила anti-repetition (плотность артиста/сессии) — в
/// `wave_constraints.dart`; здесь repetition_penalty — мягкий штраф за недавнее
/// проигрывание.
library;

import 'taste_profile.dart';

/// Кандидат в терминах фич для скоринга — оторван от Track/БД.
class ScoreCandidate {
  const ScoreCandidate({
    required this.artistKey,
    this.tags = const [],
    this.popularity = 0.0,
    this.lastPlayedSecAgo,
  });

  /// Нормализованный ключ артиста (как в профиле).
  final String artistKey;

  /// Теги кандидата (нормализованные lowercase), могут быть пустыми.
  final List<String> tags;

  /// Нормализованная популярность 0..1 (из метаданных источника).
  final double popularity;

  /// Сколько секунд назад трек последний раз звучал в волне; null — никогда.
  final int? lastPlayedSecAgo;
}

/// Веса скоринга. Пресеты характера меняют баланс exploitation/exploration.
class ScoreWeights {
  const ScoreWeights({
    this.wSim = 1.0,
    this.wNov = 0.6,
    this.wPop = 0.3,
    this.wRep = 0.8,
    this.wNeg = 1.5,
    this.explorationShare = 0.2,
  });

  final double wSim; // близость к профилю
  final double wNov; // бонус за незнакомого артиста
  final double wPop; // популярность
  final double wRep; // штраф за недавнее проигрывание
  final double wNeg; // близость к негативному профилю

  /// Доля exploration-слотов в очереди (для WaveSequencer/Фазы 3).
  final double explorationShare;

  /// «Любимое»: знакомое любимое вверх, exploration ~10%, cooldown мягче.
  static const favorite = ScoreWeights(
      wSim: 1.4, wNov: 0.15, wPop: 0.2, wRep: 0.5, explorationShare: 0.1);

  /// «Незнакомое»: exploration 60–70%, вес незнакомых артистов резко вверх.
  static const unfamiliar = ScoreWeights(
      wSim: 0.6, wNov: 1.6, wPop: 0.2, wRep: 0.9, explorationShare: 0.65);

  /// «Популярное»: вес популярности вверх.
  static const popular = ScoreWeights(
      wSim: 1.2, wNov: 0.15, wPop: 1.6, wRep: 0.7, explorationShare: 0.08);

  static const balanced = ScoreWeights();
}

/// Cooldown-окно для мягкого штрафа за повтор (в секундах).
const int kRepetitionWindowSec = 7 * 86400;

/// Скорер: считает score(t) по профилю [p] и весам [weights].
class Scorer {
  const Scorer(this.profile,
      {this.weights = ScoreWeights.balanced,
      this.alpha = ProfileConfig.defaultAlpha});

  final TasteProfile profile;
  final ScoreWeights weights;
  final double alpha;

  double score(ScoreCandidate c) {
    final sim = _similarity(c);
    final nov = profile.isKnownArtist(c.artistKey) ? 0.0 : 1.0;
    final pop = c.popularity.clamp(0.0, 1.0);
    final rep = _repetitionPenalty(c);
    final neg = _negativeAffinity(c);
    return weights.wSim * sim +
        weights.wNov * nov +
        weights.wPop * pop -
        weights.wRep * rep -
        weights.wNeg * neg;
  }

  double _similarity(ScoreCandidate c) {
    var s = profile.artistAffinity(c.artistKey, alpha: alpha);
    if (c.tags.isNotEmpty) {
      var tagSum = 0.0;
      for (final t in c.tags) {
        tagSum += profile.tagAffinity(t);
      }
      s += tagSum / c.tags.length;
    }
    return _squash(s);
  }

  double _negativeAffinity(ScoreCandidate c) {
    var n = profile.negativeArtistAffinity(c.artistKey);
    if (c.tags.isNotEmpty) {
      var ts = 0.0;
      for (final t in c.tags) {
        ts += profile.negativeTagAffinity(t);
      }
      n += ts / c.tags.length;
    }
    return _squash(n);
  }

  double _repetitionPenalty(ScoreCandidate c) {
    final ago = c.lastPlayedSecAgo;
    if (ago == null || ago >= kRepetitionWindowSec) return 0.0;
    if (ago <= 0) return 1.0;
    return 1.0 - ago / kRepetitionWindowSec; // 1 (только что) → 0 (окно прошло)
  }

  /// Мягкое сжатие к (−1, 1), чтобы один переслушанный артист не доминировал.
  static double _squash(double x) {
    if (!x.isFinite) return 0.0;
    return x / (1 + x.abs());
  }
}
