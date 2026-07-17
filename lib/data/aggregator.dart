import 'package:flutter/foundation.dart';

import '../core/diagnostics.dart';
import '../core/net/net_errors.dart';
import '../domain/models/playable_stream.dart';
import '../domain/models/source_type.dart';
import '../domain/models/track.dart';
import '../domain/music_source.dart';
import 'recs/recs_dedup.dart';
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

  Set<SourceType> get enabled => _enabled;
  void setEnabled(Set<SourceType> e) {
    _enabled = e;
    clearCache();
  }

  /// Сбрасывает кэш ленты и поиска (смена источников, pull-to-refresh).
  void clearCache() {
    _feedCache = null;
    _feedAt = null;
    _searchCache.clear();
  }

  Iterable<MusicSource> get _active =>
      _sources.entries.where((e) => _enabled.contains(e.key)).map((e) => e.value);

  MusicSource sourceFor(SourceType t) => _sources[t]!;

  Future<bool> isReady(SourceType t) =>
      _enabled.contains(t) ? _sources[t]!.isReady : Future.value(false);

  /// Поиск по всем включённым источникам, результаты «переплетаются»
  /// (round-robin), чтобы лента не была занята одним сервисом.
  Future<List<Track>> search(String query, {int perSource = 15}) async {
    final key = '$query::$perSource';
    final hit = _searchCache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _searchTtl) {
      return hit.tracks;
    }
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
  }

  Future<List<Track>> feed({int perSource = 12}) async {
    final cached = _feedCache;
    final at = _feedAt;
    if (cached != null && at != null &&
        DateTime.now().difference(at) < _feedTtl) {
      return cached;
    }
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
      } catch (_) {/* уходим в фолбэк-поиск */}
    }
    final q = '${track.artist} ${track.album ?? ''}'.trim();
    return q.isEmpty ? const [] : search(q);
  }

  Future<PlayableStream> resolveStream(Track track) =>
      _sources[track.source]!.resolveStream(track);

  /// Сбрасывает кэш резолва потока для трека (вызывается при ошибке
  /// воспроизведения — чтобы перерезолв взял свежую ссылку, а не битую из кэша).
  void evictStreamCache(Track track) {
    final s = _sources[track.source];
    if (s is YoutubeMusicSource) s.evictStreamCache(track.id);
  }

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

  /// Порядок источников для подмены: YouTube первым (самый доступный/бесплатный),
  /// затем остальные включённые, кроме родного [exclude].
  Iterable<SourceType> _fallbackOrder(SourceType exclude) => [
        SourceType.youtube,
        ...SourceType.values.where((t) => t != SourceType.youtube),
      ].where((t) =>
          t != exclude && _enabled.contains(t) && _sources[t] != null);

  /// Из выдачи поиска выбирает трек, который действительно совпадает с искомым
  /// [want] (тот же артист+название), отсекая каверы/чужие треки.
  @visibleForTesting
  static Track? pickMatch(Track want, List<Track> results) {
    for (final t in results) {
      if (RecsDedup.resolvesTo(want.artist, want.title, t.artist, t.title)) {
        return t;
      }
    }
    return null;
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
  Future<({PlayableStream stream, Track track})?> resolveFromOtherSources(
      Track track, {Object? nativeErr}) async {
    final query = '${track.artist} ${track.title}'.trim();
    if (query.isEmpty) return null;
    // Если ни один источник не резолвится из-за недоступности DNS — это не
    // «трека нет», а блокировка/неверный DNS (часто у VPN). Пишем явно.
    Object? dnsErr =
        (nativeErr != null && isDnsBlockError(nativeErr)) ? nativeErr : null;
    for (final t in _fallbackOrder(track.source)) {
      try {
        final src = _sources[t]!;
        final match = _pickMatch(track, await src.search(query, limit: 5));
        if (match == null) continue;
        final stream = await src.resolveStream(match);
        Diagnostics.instance.info('agg.fallback',
            '${track.source.id} → ${t.id}: «${track.artist} — ${track.title}»');
        return (stream: stream, track: match);
      } catch (e) {
        if (isDnsBlockError(e)) dnsErr = e;
      }
    }
    if (dnsErr != null) _logDnsBlock(dnsErr);
    return null;
  }

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
