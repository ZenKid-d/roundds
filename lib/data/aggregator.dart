import '../core/diagnostics.dart';
import '../domain/models/playable_stream.dart';
import '../domain/models/source_type.dart';
import '../domain/models/track.dart';
import '../domain/music_source.dart';
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

  Future<PlayableStream> resolveStream(Track track) =>
      _sources[track.source]!.resolveStream(track);

  /// Сбрасывает кэш резолва потока для трека (вызывается при ошибке
  /// воспроизведения — чтобы перерезолв взял свежую ссылку, а не битую из кэша).
  void evictStreamCache(Track track) {
    final s = _sources[track.source];
    if (s is YoutubeMusicSource) s.evictStreamCache(track.id);
  }

  /// Ищет ту же песню на YouTube (для фолбэка загрузки/воспроизведения, когда
  /// родной источник отдаёт HLS или недоступен). null — YouTube выключен/не
  /// нашёл. Для YouTube-трека возвращает его же.
  Future<Track?> youtubeMatch(Track track) async {
    if (track.source == SourceType.youtube) return track;
    final yt = _sources[SourceType.youtube];
    if (yt == null || !_enabled.contains(SourceType.youtube)) return null;
    try {
      final r = await yt.search('${track.artist} ${track.title}'.trim(), limit: 1);
      return r.isNotEmpty ? r.first : null;
    } catch (_) {
      return null;
    }
  }

  /// Резолв с умной маршрутизацией: если родной источник не отдал поток
  /// (например, трек на SoundCloud доступен только по подписке Go+, или ошибка),
  /// берём ту же песню из YouTube — бесплатного источника. Это НЕ обход
  /// пейволла SoundCloud, а переход на доступный источник того же трека.
  Future<PlayableStream> resolveStreamWithFallback(Track track) async {
    try {
      return await _sources[track.source]!.resolveStream(track);
    } catch (e) {
      final yt = _sources[SourceType.youtube];
      final canFallback = track.source != SourceType.youtube &&
          yt != null &&
          _enabled.contains(SourceType.youtube);
      if (canFallback) {
        final query = '${track.artist} ${track.title}'.trim();
        final results = await yt.search(query, limit: 1);
        if (results.isNotEmpty) {
          return await yt.resolveStream(results.first);
        }
      }
      rethrow;
    }
  }

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
