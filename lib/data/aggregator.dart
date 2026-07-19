import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/diagnostics.dart';
import '../core/net/net_errors.dart';
import '../domain/constants.dart';
import '../domain/models/artist_profile.dart';
import '../domain/models/playable_stream.dart';
import '../domain/models/source_type.dart';
import '../domain/models/track.dart';
import '../domain/music_source.dart';
import 'recs/recs_dedup.dart';
import 'sources/soundcloud_source.dart';
import 'sources/vk_source.dart';
import 'sources/yandex_source.dart';
import 'sources/youtube_music_source.dart';

/// Сводит включённые источники в единый поиск/ленту и маршрутизирует
/// резолв потока к нужному источнику.
class Aggregator {
  Aggregator(this._sources, {Set<SourceType>? enabled})
      : _enabled = enabled ?? SourceType.values.toSet();

  final Map<SourceType, MusicSource> _sources;
  Set<SourceType> _enabled;

  // Кэш ленты и поиска: сетевые запросы по всем источникам дороги, а лента и
  // повторные запросы (жанр-радио, страница артиста) часто одинаковы. TTL
  // держит данные свежими, но убирает лишние походы в сеть при каждом входе.
  static const _feedTtl = Duration(minutes: 6);
  static const _searchTtl = Duration(minutes: 5);
  List<Track>? _feedCache;
  DateTime? _feedAt;
  final Map<String, ({DateTime at, List<Track> tracks})> _searchCache = {};

  // Дедуп одновременных запросов: быстрый ввод в поиске или параллельные
  // экраны могут запросить один и тот же query/фид, пока первый запрос ещё
  // летит по сети. Вместо повторного похода в сеть отдаём тот же Future.
  final Map<String, Future<List<Track>>> _searchInFlight = {};
  Future<List<Track>>? _feedInFlight;

  // Кэш кросс-источника: когда родной источник трека за пейволлом (Go+) или
  // заблокирован, мы нашли ТУ ЖЕ песню у другого сервиса. TTL = срок жизни
  // подписанной ссылки (см. defaultStreamExpiry) — после протухания перерезолв.
  // Ключ — uid исходного трека, не найденного: на него завязан evict.
  final Map<String, ({DateTime at, PlayableStream stream, Track via})>
      _fallbackCache = {};

  // Кэш результатов поиска фолбэка по нормализованному ключу artist|title.
  // Если в очереди несколько треков одного артиста или радио крутит похожее —
  // повторный фолбэк не идёт в сеть за тем же поиском. TTL как у поиска (5 мин).
  static const _fallbackSearchTtl = Duration(minutes: 5);
  final Map<String, ({DateTime at, Map<SourceType, List<Track>> bySource})>
      _fallbackSearchCache = {};

  /// Ищет тот же трек (artist+title), уже скачанный оффлайн из другого
  /// источника — самый быстрый и надёжный кандидат фолбэка (сеть не нужна
  /// вообще). Ставится из DownloadsController.localMatchByNormKey в main().
  ({Track track, String path})? Function(String artist, String title)?
      localMatchResolver;

  Set<SourceType> get enabled => _enabled;
  void setEnabled(Set<SourceType> e) {
    _enabled = e;
    clearCache();
  }

  /// Предпочтительный источник для подмены (null — авто, YT первым). См.
  /// [_fallbackOrder]. Ставится из настроек; инвалидирует кэш фолбэка, т.к.
  /// иначе в кэше останутся подмены по старому приоритету.
  SourceType? _preferredFallback;
  void setPreferredFallback(SourceType? t) {
    if (_preferredFallback == t) return;
    _preferredFallback = t;
    _fallbackCache.clear();
    _fallbackSearchCache.clear();
  }

  /// Сбрасывает кэш ленты и поиска (смена источников, pull-to-refresh).
  void clearCache() {
    _feedCache = null;
    _feedAt = null;
    _searchCache.clear();
    _fallbackCache.clear();
    _fallbackSearchCache.clear();
  }

  Iterable<MusicSource> get _active =>
      _sources.entries.where((e) => _enabled.contains(e.key)).map((e) => e.value);

  MusicSource sourceFor(SourceType t) => _sources[t]!;

  Future<bool> isReady(SourceType t) =>
      _enabled.contains(t) ? _sources[t]!.isReady : Future.value(false);

  /// Поиск по всем включённым источникам, результаты «переплетаются»
  /// (round-robin), чтобы лента не была занята одним сервисом.
  Future<List<Track>> search(String query, {int perSource = 15}) {
    final key = '$query::$perSource';
    final hit = _searchCache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _searchTtl) {
      return Future.value(hit.tracks);
    }
    final inFlight = _searchInFlight[key];
    if (inFlight != null) return inFlight;
    final future = _runSearch(query, perSource, key);
    _searchInFlight[key] = future;
    return future;
  }

  Future<List<Track>> _runSearch(
      String query, int perSource, String key) async {
    try {
      final futures = _active.map((s) async {
        try {
          return await s.search(query, limit: perSource);
        } catch (e) {
          _logDnsBlock(e);
          Diagnostics.instance.warn('agg.search', '${s.type.id} «$query»: $e');
          return <Track>[];
        }
      });
      final lists = await Future.wait(futures);
      final result = _interleave(lists);
      if (result.isNotEmpty) {
        _searchCache[key] = (at: DateTime.now(), tracks: result);
        if (_searchCache.length > 32) {
          _searchCache.remove(_searchCache.keys.first);
        }
      }
      return result;
    } finally {
      _searchInFlight.remove(key);
    }
  }

  Future<List<Track>> feed({int perSource = 12}) {
    final cached = _feedCache;
    final at = _feedAt;
    if (cached != null && at != null &&
        DateTime.now().difference(at) < _feedTtl) {
      return Future.value(cached);
    }
    final inFlight = _feedInFlight;
    if (inFlight != null) return inFlight;
    final future = _runFeed(perSource);
    _feedInFlight = future;
    return future;
  }

  Future<List<Track>> _runFeed(int perSource) async {
    try {
      final futures = _active.map((s) async {
        try {
          return await s.feed(limit: perSource);
        } catch (e) {
          Diagnostics.instance.warn('agg.feed', '${s.type.id}: $e');
          return <Track>[];
        }
      });
      final lists = await Future.wait(futures);
      final result = _interleave(lists);
      if (result.isNotEmpty) {
        _feedCache = result;
        _feedAt = DateTime.now();
      }
      return result;
    } finally {
      _feedInFlight = null;
    }
  }

  /// Треклист альбома, к которому принадлежит [track]. Нативно умеет Яндекс
  /// (по albumId из extra); для остальных источников — фолбэк на поиск
  /// «артист альбом», чтобы страница альбома всё равно что-то показала.
  Future<List<Track>> albumTracks(Track track) async {
    final albumId = track.extra['albumId'] as String?;
    final src = _sources[track.source];
    if (src is YandexSource &&
        albumId != null &&
        _enabled.contains(SourceType.yandex)) {
      try {
        final tracks = await src.albumTracks(albumId);
        if (tracks.isNotEmpty) return tracks;
      } catch (e) {
        // Не упёрлись в треклист альбома — уходим в фолбэк-поиск, но причину
        // (протухший токен, изменение API Яндекса) сохраняем для диагностики.
        Diagnostics.instance
            .warn('aggregator', 'albumTracks($albumId) Яндекса упал: $e');
      }
    }
    final q = '${track.artist} ${track.album ?? ''}'.trim();
    return q.isEmpty ? const [] : search(q);
  }

  /// Профиль исполнителя (аватар/баннер/подписчики/био) для страницы артиста.
  /// Умеют SoundCloud (по id автора трека), YouTube Music (по имени —
  /// отдельный поиск карточки исполнителя + browse её канала), Яндекс Музыка
  /// (по id артиста трека) и VK (по owner_id — но там это владелец записи,
  /// не обязательно артист, см. [ArtistProfile.isRecordOwner]).
  Future<ArtistProfile?> artistProfile(Track seed) async {
    final src = _sources[seed.source];
    if (!_enabled.contains(seed.source)) return null;
    try {
      if (src is SoundcloudSource) return await src.artistProfile(seed);
      if (src is YoutubeMusicSource) {
        return await src.artistProfile(seed.artist);
      }
      if (src is YandexSource) return await src.artistProfile(seed);
      if (src is VkSource) return await src.artistProfile(seed);
      return null;
    } catch (e) {
      Diagnostics.instance.warn('aggregator', 'artistProfile упал: $e');
      return null;
    }
  }

  Future<PlayableStream> resolveStream(Track track) =>
      _sources[track.source]!.resolveStream(track);

  /// Сбрасывает кэш резолва потока для трека (вызывается при ошибке
  /// воспроизведения — чтобы перерезолв взял свежую ссылку, а не битую из кэша).
  void evictStreamCache(Track track) {
    final s = _sources[track.source];
    if (s is YoutubeMusicSource) s.evictStreamCache(track.id);
    evictFallbackCache(track.uid);
  }

  /// Сбрасывает кэш кросс-источника для [uid] — при ошибке воспроизведения
  /// подменной ссылки, чтобы перерезолв взял свежий поток, а не битый из кэша.
  void evictFallbackCache(String uid) => _fallbackCache.remove(uid);

  /// Ищет ту же песню на YouTube (для фолбэка загрузки, когда родной источник
  /// отдаёт HLS или недоступен). null — YouTube выключен/не нашёл. Для
  /// YouTube-трека возвращает его же. Совпадение проверяем строго ([_pickMatch]),
  /// чтобы не подсунуть чужой трек/кавер под тем же названием.
  Future<Track?> youtubeMatch(Track track) async {
    if (track.source == SourceType.youtube) return track;
    final yt = _sources[SourceType.youtube];
    if (yt == null || !_enabled.contains(SourceType.youtube)) return null;
    try {
      final r = await yt.search('${track.artist} ${track.title}'.trim(), limit: 5);
      return _pickMatch(track, r);
    } catch (_) {
      return null;
    }
  }

  /// Порядок источников для подмены: предпочтительный пользователем первым
  /// (если задан), затем YouTube (самый доступный/бесплатный по умолчанию),
  /// затем остальные включённые, кроме родного [exclude].
  Iterable<SourceType> _fallbackOrder(SourceType exclude) => [
        if (_preferredFallback != null) _preferredFallback!,
        SourceType.youtube,
        ...SourceType.values.where((t) =>
            t != SourceType.youtube && t != _preferredFallback),
      ].where((t) =>
          t != exclude && _enabled.contains(t) && _sources[t] != null);

  /// Из выдачи поиска выбирает трек, который действительно совпадает с искомым
  /// [want] (тот же артист+название), отсекая каверы/чужие треки.
  @visibleForTesting
  static Track? pickMatch(Track want, List<Track> results) =>
      bestMatch(want, results)?.match;

  /// Ранжирует кандидатов из [results] по [RecsDedup.matchScore] (название +
  /// артист + длительность) и возвращает лучшего со счётом. null — если ни один
  /// не прошёл порог. Используется кросс-источником для выбора лучшей версии
  /// трека (полная против радио-эдита, дубль с той же длительностью и т.д.).
  @visibleForTesting
  static ({Track match, double score})? bestMatch(
      Track want, List<Track> results) {
    ({Track match, double score})? best;
    for (final t in results) {
      final s = RecsDedup.matchScore(
        wantArtist: want.artist,
        wantTitle: want.title,
        gotArtist: t.artist,
        gotTitle: t.title,
        wantDuration: want.duration,
        gotDuration: t.duration,
      );
      if (s == null) continue;
      if (best == null || s > best.score) best = (match: t, score: s);
    }
    return best;
  }

  Track? _pickMatch(Track want, List<Track> results) => pickMatch(want, results);

  /// Резолв с умной маршрутизацией: если родной источник не отдал поток
  /// (например, трек на SoundCloud доступен только по подписке Go+, отключён или
  /// ошибка), ищем ТУ ЖЕ песню в других включённых источниках и играем оттуда.
  /// Возвращает поток и трек, который его реально отдал (его [Track.source] —
  /// для видимой пометки «через <сервис>»). Это НЕ обход пейволла, а переход на
  /// доступный источник того же трека.
  Future<({PlayableStream stream, Track track})> resolveWithSource(
      Track track) async {
    Object? firstErr;
    try {
      return (
        stream: await _sources[track.source]!.resolveStream(track),
        track: track,
      );
    } catch (e) {
      firstErr = e;
    }
    final viaOther = await resolveFromOtherSources(track, nativeErr: firstErr);
    if (viaOther != null) return viaOther;
    throw firstErr; // нигде не нашли — исходная ошибка родного источника
  }

  /// Резолвит ТУ ЖЕ песню из ДРУГИХ включённых источников (кроме родного [track]).
  /// Используется и как фолбэк резолва (родной кинул ошибку — [nativeErr]), и как
  /// подмена при СБОЕ ВОСПРОИЗВЕДЕНИЯ (родной зарезолвился, но медиа не играет —
  /// напр. YouTube googlevideo режется провайдером, а SoundCloud играет).
  /// null — если ни один другой источник не дал играбельный поток.
  ///
  /// Идёт ПАРАЛЛЕЛЬНО по всем фолбэк-источникам (один медленный не блокирует
  /// остальных), выбирает лучшего кандидата по [RecsDedup.matchScore] (название +
  /// артист + длительность) и резолвит его. Результат кэшируется на срок жизни
  /// подписанной ссылки ([defaultStreamExpiry]).
  Future<({PlayableStream stream, Track track})?> resolveFromOtherSources(
      Track track, {Object? nativeErr}) async {
    final query = '${track.artist} ${track.title}'.trim();
    if (query.isEmpty) return null;

    // Кэш: недавно находили подмену для этого трека — отдаём сразу, без сети.
    final cached = _fallbackCache[track.uid];
    if (cached != null &&
        DateTime.now().difference(cached.at) < defaultStreamExpiry &&
        !cached.stream.isExpired) {
      return (stream: cached.stream, track: cached.via);
    }

    // Офлайн-дубль той же песни (скачан из другого источника) — самый
    // быстрый и надёжный кандидат: сеть не нужна вообще, файл не протухает.
    final local = localMatchResolver?.call(track.artist, track.title);
    if (local != null) {
      final stream = PlayableStream(uri: Uri.file(local.path));
      Diagnostics.instance.info('agg.fallback',
          '${track.source.id} → офлайн-дубль «${track.artist} — ${track.title}»');
      _fallbackCache[track.uid] =
          (at: DateTime.now(), stream: stream, via: local.track);
      return (stream: stream, track: local.track);
    }

    final paywalled = nativeErr != null && _isGoPlusErr(nativeErr);
    if (paywalled) {
      // Это не сбой сети, а пейволл родного источника (Go+) — логируем тише:
      // переход на кросс-источник штатный, не ошибка.
      Diagnostics.instance.info('agg.paywall',
          '${track.source.id} «${track.title}»: трек за подпиской — ищем в других источниках');
    }

    // Параллельный поиск по всем фолбэк-источникам с таймаутом 8с на каждый:
    // один зависший/медленный сервис не задержит остальные. Результаты поиска
    // кэшируются по normKey — несколько треков одного артиста в очереди не
    // приведут к повторным сетевым запросам за той же выдачей.
    final normKey = RecsDedup.normKey(track.artist, track.title);
    final sw = Stopwatch()..start();
    final order = _fallbackOrder(track.source).toList();
    Object? dnsErr =
        (nativeErr != null && isDnsBlockError(nativeErr)) ? nativeErr : null;

    // Если для этого artist|title уже искали недавно — переиспользуем выдачу,
    // в сеть не идём (только резолв победителя ниже).
    final cachedSearch = _fallbackSearchCache[normKey];
    final useCache = cachedSearch != null &&
        DateTime.now().difference(cachedSearch.at) < _fallbackSearchTtl;

    final List<({SourceType source, List<Track> results, Object? err})> searches;
    if (useCache) {
      // Восстанавливаем поисковые записи из кэша; исключаем родной источник
      // (он уже не отдал поток — нет смысла перебирать его кандидатов).
      searches = order.map((t) {
        final results = cachedSearch.bySource[t] ?? const <Track>[];
        return (source: t, results: results, err: null);
      }).toList();
    } else {
      final searchFutures = order.map((t) async {
        try {
          final src = _sources[t]!;
          final r = await src.search(query, limit: 5).timeout(
                const Duration(seconds: 8),
                onTimeout: () => const <Track>[],
              );
          return (source: t, results: r, err: null);
        } catch (e) {
          if (isDnsBlockError(e)) {
            return (source: t, results: const <Track>[], err: e);
          }
          return (source: t, results: const <Track>[], err: null);
        }
      });
      searches = await Future.wait(searchFutures);

      // Сохраняем свежую выдачу по normKey для следующих треков той же песни.
      _fallbackSearchCache[normKey] = (
        at: DateTime.now(),
        bySource: {
          for (final e in searches) e.source: e.results,
        },
      );
      if (_fallbackSearchCache.length > 32) {
        _fallbackSearchCache.remove(_fallbackSearchCache.keys.first);
      }
    }

    // Собираем прошедших порог кандидатов со счётом.
    final candidates = <({Track match, SourceType source, double score})>[];
    for (final entry in searches) {
      if (entry.err != null) dnsErr ??= entry.err;
      for (final r in entry.results) {
        final s = RecsDedup.matchScore(
          wantArtist: track.artist,
          wantTitle: track.title,
          gotArtist: r.artist,
          gotTitle: r.title,
          wantDuration: track.duration,
          gotDuration: r.duration,
        );
        if (s == null) continue;
        candidates.add((match: r, source: entry.source, score: s));
      }
    }
    if (candidates.isEmpty) {
      if (dnsErr != null) _logDnsBlock(dnsErr);
      return null;
    }

    // Сортировка: по счёту desc, при равенстве — по приоритету источника
    // (_fallbackOrder: YT первым как самый доступный).
    final orderIndex = {for (var i = 0; i < order.length; i++) order[i]: i};
    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return (orderIndex[a.source] ?? 99)
          .compareTo(orderIndex[b.source] ?? 99);
    });

    // Метрика для отладки матчинга: топ-3 кандидатов со счётом по источникам.
    final top3 = candidates.take(3).map((c) =>
        '${c.source.id}:${(c.score * 100).round()}%').join(', ');
    Diagnostics.instance.info('agg.fallback.candidates',
        '${track.source.id} «${track.artist} — ${track.title}»: '
        '${candidates.length} кандидатов, top: $top3');

    // Резолвим победителя; при неудаче — топ-3 следующих из шорт-листа, не
    // возвращаясь к поиску (уже отдали в сеть).
    for (final c in candidates.take(3)) {
      try {
        final src = _sources[c.source]!;
        final stream = await src.resolveStream(c.match);
        Diagnostics.instance.info('agg.fallback',
            '${track.source.id} → ${c.source.id}: «${track.artist} — ${track.title}» '
            '(score ${c.score.toStringAsFixed(2)}, ${sw.elapsedMilliseconds}мс)');
        _fallbackCache[track.uid] = (
          at: DateTime.now(),
          stream: stream,
          via: c.match,
        );
        return (stream: stream, track: c.match);
      } catch (e) {
        if (isDnsBlockError(e)) dnsErr = e;
      }
    }
    if (dnsErr != null) _logDnsBlock(dnsErr);
    return null;
  }

  /// Опознаёт маркер пейволла SoundCloud Go+ в ошибке родного источника.
  /// См. [SoundcloudSource.goPlusMarker] — кидает SourceException со стабильным
  /// префиксом, чтобы отличить пейволл от сетевого сбоя/блокировки.
  @visibleForTesting
  static bool isGoPlusErr(Object err) {
    final msg = err is SourceException
        ? err.message
        : err is Exception
            ? err.toString()
            : '$err';
    // Проверяем по стабильному префиксу маркера («SC_GO_PLUS»), не по полному
    // тексту — формулировка сообщения может меняться, префикс — нет.
    return msg.contains(SoundcloudSource.goPlusMarker.split(':').first);
  }

  static bool _isGoPlusErr(Object err) => isGoPlusErr(err);

  /// Пишет понятную запись `net.dns`, если ошибка — недоступность хоста (DNS).
  void _logDnsBlock(Object error) {
    if (!isDnsBlockError(error)) return;
    final host = blockedHostOf(error);
    Diagnostics.instance.warn(
      'net.dns',
      '${host ?? 'хост'} не резолвится — сеть блокирует доступ. '
          'Смените VPN/DNS (напр. Приватный DNS: dns.google).',
    );
  }

  /// Тонкая обёртка для вызовов, которым нужен только поток.
  Future<PlayableStream> resolveStreamWithFallback(Track track) async =>
      (await resolveWithSource(track)).stream;

  List<Track> _interleave(List<List<Track>> lists) {
    final out = <Track>[];
    final seen = <String>{};
    var i = 0;
    var added = true;
    while (added) {
      added = false;
      for (final list in lists) {
        if (i < list.length) {
          added = true;
          final t = list[i];
          if (seen.add(t.uid)) out.add(t);
        }
      }
      i++;
    }
    return out;
  }
}
