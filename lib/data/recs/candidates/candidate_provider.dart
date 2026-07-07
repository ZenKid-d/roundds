/// Recs v2 — интерфейс генерации кандидатов. Каждый источник графа похожести
/// (Last.fm, native related SoundCloud/YouTube/Яндекс, local-history) —
/// отдельная pluggable-реализация. Недоступный провайдер (нет ключа/токена/
/// выключенный источник) возвращает пустой список, а не падает.
library;

import '../../../domain/models/track.dart';
import '../recs_dedup.dart';

/// Сырой кандидат до резолва в играбельный трек. [resolved] заполнен, если
/// провайдер уже вернул готовый [Track] (native related-эндпоинты); Last.fm
/// отдаёт только (artist, title) — их резолвит агрегатор.
class RawCandidate {
  const RawCandidate({
    required this.artist,
    required this.title,
    this.weight = 0.0,
    this.tags = const [],
    this.popularity = 0.0,
    this.resolved,
  });

  final String artist;
  final String title;

  /// Сила связи от провайдера (Last.fm match и т.п.), 0..1.
  final double weight;
  final List<String> tags;

  /// Нормализованная популярность 0..1, если известна из метаданных.
  final double popularity;

  /// Уже играбельный трек (если провайдер вернул Track).
  final Track? resolved;

  /// Нормализованный ключ для дедупа кросс-источников.
  String get dedupKey => RecsDedup.normKey(artist, title);
}

/// Запрос к провайдерам: сиды-треки + топ-артисты/теги профиля + лимиты.
class CandidateQuery {
  const CandidateQuery({
    this.seeds = const [],
    this.seedArtists = const [],
    this.seedTags = const [],
    this.limitPerSeed = 20,
  });

  final List<Track> seeds;
  final List<String> seedArtists;
  final List<String> seedTags;
  final int limitPerSeed;
}

abstract class CandidateProvider {
  /// Стабильный id для логов/кэша.
  String get id;

  /// Доступен ли провайдер сейчас (ключ/токен/включённый источник).
  Future<bool> get isAvailable;

  Future<List<RawCandidate>> fetch(CandidateQuery query);
}
