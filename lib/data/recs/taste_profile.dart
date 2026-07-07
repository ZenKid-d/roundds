/// Recs v2 — профиль вкуса. Взвешенные словари `artist → weight` и
/// `tag → weight` с экспоненциальным затуханием по времени (half-life ≈ 30 дней),
/// в трёх ипостасях: долгосрочный (вся история), краткосрочный (последняя
/// сессия) и негативный (дизлайки/жёсткие скипы). Всё чистое — строится в
/// изоляте и в тестах, без БД/сети.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'recs_dedup.dart';
import 'recs_signals.dart';

/// Минимальное представление события для построения профиля. Оторвано от БД:
/// [artist] — сырое имя (нормализуется внутри), [tags] могут быть пустыми.
class ProfileEvent {
  const ProfileEvent({
    required this.artist,
    required this.kind,
    required this.tsSec,
    this.tags = const [],
  });

  final String artist;
  final SignalKind kind;
  final int tsSec; // unix-секунды
  final List<String> tags;
}

/// Тюнящиеся константы профиля — все в одном месте.
class ProfileConfig {
  const ProfileConfig._();

  /// Период полураспада веса события.
  static const double halfLifeDays = 30;

  /// Сколько последних событий формируют краткосрочный («сессионный») профиль.
  static const int shortWindow = 18;

  /// Доля краткосрочного профиля в миксе: `α·short + (1−α)·long`.
  static const double defaultAlpha = 0.4;
}

/// Экспоненциальное затухание: множитель веса события через [deltaSec] секунд
/// после него равен `0.5^(Δt / half-life)`.
double decayFactor(int deltaSec,
    {double halfLifeDays = ProfileConfig.halfLifeDays}) {
  if (deltaSec <= 0) return 1.0;
  final halfLifeSec = halfLifeDays * 86400.0;
  return math.pow(0.5, deltaSec / halfLifeSec).toDouble();
}

/// Снимок профиля вкуса.
class TasteProfile {
  const TasteProfile({
    this.longArtists = const {},
    this.shortArtists = const {},
    this.negArtists = const {},
    this.longTags = const {},
    this.negTags = const {},
    this.heardArtists = const {},
  });

  /// Долгосрочные веса артистов (вся история с затуханием).
  final Map<String, double> longArtists;

  /// Краткосрочные веса артистов (последняя сессия).
  final Map<String, double> shortArtists;

  /// Негативные веса артистов (величина «неприязни», ≥ 0).
  final Map<String, double> negArtists;

  final Map<String, double> longTags;
  final Map<String, double> negTags;

  /// Артисты, которых пользователь вообще когда-либо слышал (для novelty).
  final Set<String> heardArtists;

  static const TasteProfile empty = TasteProfile();

  /// Смешанный вес артиста: `α·short + (1−α)·long`. Сессия рулит направлением,
  /// база держит вкус — это и даёт «живое» ощущение волны.
  double artistAffinity(String artistKey,
      {double alpha = ProfileConfig.defaultAlpha}) {
    final s = shortArtists[artistKey] ?? 0;
    final l = longArtists[artistKey] ?? 0;
    return alpha * s + (1 - alpha) * l;
  }

  /// Копия профиля с наложенными на краткосрочную часть сессионными дельтами
  /// (real-time направление волны: скипы топят, лайки поднимают артистов).
  TasteProfile withSessionOverrides(Map<String, double> deltas) {
    if (deltas.isEmpty) return this;
    final merged = {...shortArtists};
    deltas.forEach((k, v) => merged[k] = (merged[k] ?? 0) + v);
    return TasteProfile(
      longArtists: longArtists,
      shortArtists: merged,
      negArtists: negArtists,
      longTags: longTags,
      negTags: negTags,
      heardArtists: heardArtists,
    );
  }

  double tagAffinity(String tag) => longTags[tag] ?? 0;

  double negativeArtistAffinity(String artistKey) => negArtists[artistKey] ?? 0;
  double negativeTagAffinity(String tag) => negTags[tag] ?? 0;

  /// Слышал ли пользователь этого артиста (нормализованный ключ) хоть раз.
  bool isKnownArtist(String artistKey) => heardArtists.contains(artistKey);

  /// Топ-артисты по долгосрочному весу (для сидов рядов/дневных плейлистов).
  List<String> topArtists({int limit = 20}) {
    final entries = longArtists.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(limit)) e.key];
  }

  /// Топ-теги по долгосрочному весу.
  List<String> topTags({int limit = 20}) {
    final entries = longTags.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(limit)) e.key];
  }

  Map<String, Object?> toJson() => {
        'longArtists': longArtists,
        'shortArtists': shortArtists,
        'negArtists': negArtists,
        'longTags': longTags,
        'negTags': negTags,
        'heardArtists': heardArtists.toList(),
      };

  String encode() => jsonEncode(toJson());

  static TasteProfile decode(String raw) {
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return empty;
    }
  }

  static TasteProfile fromJson(Map<String, dynamic> j) => TasteProfile(
        longArtists: _numMap(j['longArtists']),
        shortArtists: _numMap(j['shortArtists']),
        negArtists: _numMap(j['negArtists']),
        longTags: _numMap(j['longTags']),
        negTags: _numMap(j['negTags']),
        heardArtists: {
          for (final e in (j['heardArtists'] as List? ?? const []))
            e as String,
        },
      );

  static Map<String, double> _numMap(Object? o) {
    if (o is! Map) return const {};
    return {
      for (final e in o.entries)
        e.key as String: (e.value as num).toDouble(),
    };
  }
}

/// Строитель профиля из плоского списка событий. Чистая функция —
/// пригодна для `Isolate.run`.
class TasteProfileBuilder {
  const TasteProfileBuilder._();

  static TasteProfile build(
    List<ProfileEvent> events, {
    required int nowSec,
    int shortWindow = ProfileConfig.shortWindow,
    double halfLifeDays = ProfileConfig.halfLifeDays,
  }) {
    final longArtists = <String, double>{};
    final longTags = <String, double>{};
    final negArtists = <String, double>{};
    final negTags = <String, double>{};
    final heard = <String>{};

    for (final e in events) {
      final artistKey = RecsDedup.normalize(e.artist);
      if (artistKey.isNotEmpty) heard.add(artistKey);

      final w = RecsWeights.of(e.kind);
      if (w == 0) continue; // нейтральные (start/play) — только для heard

      final decay = decayFactor(nowSec - e.tsSec, halfLifeDays: halfLifeDays);
      final contribution = w * decay;
      _add(longArtists, artistKey, contribution);
      for (final tag in e.tags) {
        _add(longTags, _normTag(tag), contribution);
      }
      if (w < 0) {
        // Отрицательные сигналы наполняют негативный профиль (положит. величина).
        _add(negArtists, artistKey, -contribution);
        for (final tag in e.tags) {
          _add(negTags, _normTag(tag), -contribution);
        }
      }
    }

    // Краткосрочный профиль — последние N событий по времени, без затухания
    // (сессия и так свежая), но с теми же весами сигналов.
    final recent = [...events]..sort((a, b) => b.tsSec.compareTo(a.tsSec));
    final shortArtists = <String, double>{};
    for (final e in recent.take(shortWindow)) {
      final w = RecsWeights.of(e.kind);
      if (w == 0) continue;
      _add(shortArtists, RecsDedup.normalize(e.artist), w);
    }

    return TasteProfile(
      longArtists: longArtists,
      shortArtists: shortArtists,
      negArtists: negArtists,
      longTags: longTags,
      negTags: negTags,
      heardArtists: heard,
    );
  }

  static String _normTag(String tag) => tag.toLowerCase().trim();

  static void _add(Map<String, double> m, String k, double v) {
    if (k.isEmpty) return;
    m[k] = (m[k] ?? 0) + v;
  }
}
