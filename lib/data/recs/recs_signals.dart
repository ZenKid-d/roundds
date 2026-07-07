/// Recs v2 — типы сигналов воспроизведения, их веса и классификатор скипов.
/// Всё чистое и тестируемое; веса вынесены в константы для тюнинга.
library;

/// Тип сигнала о взаимодействии с треком.
enum SignalKind {
  start, // трек начался — нейтрально
  skipHard, // <30 сек или <25%
  skipSoft, // 25–60%
  play, // 60–85% — нейтрально
  complete, // >85%
  like,
  dislike, // + hard-фильтр трека
  repeat, // повтор / очередь / добавление в плейлист
}

extension SignalKindId on SignalKind {
  String get id => name;
  static SignalKind fromId(String s) =>
      SignalKind.values.firstWhere((e) => e.name == s,
          orElse: () => SignalKind.play);
}

/// Веса сигналов для профиля вкуса (из ТЗ). Правятся в одном месте.
class RecsWeights {
  const RecsWeights._();

  static const double skipHard = -1.0;
  static const double skipSoft = -0.3;
  static const double complete = 0.5;
  static const double like = 1.5;
  static const double dislike = -2.0;
  static const double repeat = 1.0;

  /// Вес сигнала; нейтральные (start/play) — 0.
  static double of(SignalKind k) => switch (k) {
        SignalKind.skipHard => skipHard,
        SignalKind.skipSoft => skipSoft,
        SignalKind.complete => complete,
        SignalKind.like => like,
        SignalKind.dislike => dislike,
        SignalKind.repeat => repeat,
        SignalKind.start || SignalKind.play => 0.0,
      };
}

/// Классификатор факта воспроизведения по реально прослушанному времени.
class RecsSignals {
  const RecsSignals._();

  static const int hardSkipMs = 30000; // <30 сек — жёсткий скип

  /// [durationMs] <= 0 — длительность неизвестна: судим только по абсолютному
  /// времени (<30 сек = жёсткий скип, иначе нейтрально).
  static SignalKind classifyPlayback({
    required int playedMs,
    required int durationMs,
  }) {
    if (playedMs < hardSkipMs) return SignalKind.skipHard;
    if (durationMs <= 0) return SignalKind.play;
    final frac = playedMs / durationMs;
    if (frac < 0.25) return SignalKind.skipHard;
    if (frac < 0.60) return SignalKind.skipSoft;
    if (frac > 0.85) return SignalKind.complete;
    return SignalKind.play; // 60–85% — нейтрально
  }
}
