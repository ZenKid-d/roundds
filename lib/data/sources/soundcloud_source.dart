import 'package:dio/dio.dart';

import '../../domain/models/playable_stream.dart';
import '../../domain/models/source_type.dart';
import '../../domain/models/track.dart';
import '../../domain/music_source.dart';

/// Источник SoundCloud поверх внутреннего api-v2 и публичного web client_id.
/// Аудио играет ВНУТРИ нашего плеера (progressive-поток).
///
/// ⚠️ Нарушает ToS SoundCloud. client_id периодически протухает —
/// в Settings есть кнопка «обновить client_id».
class SoundcloudSource implements MusicSource {
  SoundcloudSource(this._dio, {String? cachedClientId})
      : _clientId = cachedClientId;

  final Dio _dio;
  String? _clientId;

  static const _apiBase = 'https://api-v2.soundcloud.com';

  @override
  SourceType get type => SourceType.soundcloud;

  @override
  Future<bool> get isReady async {
    try {
      await _ensureClientId();
      return _clientId != null;
    } catch (_) {
      return false;
    }
  }

  String? get clientId => _clientId;

  /// Достаём актуальный публичный client_id со страницы плеера.
  // Десктопный User-Agent — с Android-UA SoundCloud отдаёт другую страницу.
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  Future<String> refreshClientId() async {
    final page = await _dio.get<String>(
      'https://soundcloud.com/discover',
      options: Options(responseType: ResponseType.plain, headers: {
        'User-Agent': _ua,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9',
        'Accept-Language': 'en-US,en;q=0.9',
      }),
    );
    final html = page.data ?? '';
    final scripts = RegExp('<script[^>]+src="([^"]+)"')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .where((u) => u.startsWith('http') && u.endsWith('.js'))
        .toList();
    final patterns = [
      RegExp(r'client_id:"([A-Za-z0-9]{20,})"'),
      RegExp(r'"client_id":"([A-Za-z0-9]{20,})"'),
      RegExp(r'client_id=([A-Za-z0-9]{20,})'),
    ];
    for (final url in scripts.reversed) {
      try {
        final js = await _dio.get<String>(url,
            options: Options(
                responseType: ResponseType.plain,
                headers: {'User-Agent': _ua}));
        final body = js.data ?? '';
        for (final p in patterns) {
          final m = p.firstMatch(body);
          if (m != null) {
            _clientId = m.group(1);
            return _clientId!;
          }
        }
      } catch (_) {/* пробуем следующий скрипт */}
    }
    throw SourceException(type, 'не удалось получить client_id');
  }

  Future<void> _ensureClientId() async {
    if (_clientId == null) await refreshClientId();
  }

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    await _ensureClientId();
    try {
      final r = await _dio.get('$_apiBase/search/tracks', queryParameters: {
        'q': query,
        'client_id': _clientId,
        'limit': limit,
      });
      final list = (r.data['collection'] as List? ?? []);
      return list
          .whereType<Map>()
          .map((e) => _toTrack(e.cast<String, dynamic>()))
          .where((t) => t != null)
          .cast<Track>()
          .toList();
    } catch (e) {
      throw SourceException(type, 'ошибка поиска ($e)');
    }
  }

  @override
  Future<List<Track>> feed({int limit = 20}) async {
    await _ensureClientId();
    // «Лента» — популярное в основных жанрах за неделю.
    try {
      final r = await _dio.get('$_apiBase/charts', queryParameters: {
        'kind': 'top',
        'genre': 'soundcloud:genres:all-music',
        'client_id': _clientId,
        'limit': limit,
      });
      final list = (r.data['collection'] as List? ?? []);
      return list
          .map((e) => (e as Map)['track'])
          .whereType<Map>()
          .map((e) => _toTrack(e.cast<String, dynamic>()))
          .where((t) => t != null)
          .cast<Track>()
          .toList();
    } catch (_) {
      // fallback на поиск, если charts недоступны
      return search('trending', limit: limit);
    }
  }

  @override
  Future<PlayableStream> resolveStream(Track track) async {
    await _ensureClientId();
    final transcodings =
        (track.extra['transcodings'] as List?)?.cast<Map>() ?? const [];
    final progressive = transcodings.firstWhere(
      (t) => (t['format']?['protocol']) == 'progressive',
      orElse: () => transcodings.isNotEmpty ? transcodings.first : {},
    );
    final url = progressive['url'] as String?;
    if (url == null) {
      throw SourceException(type, 'нет доступного потока для трека');
    }
    try {
      final r = await _dio.get(url, queryParameters: {'client_id': _clientId});
      final streamUrl = r.data['url'] as String;
      return PlayableStream(
        uri: Uri.parse(streamUrl),
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );
    } catch (e) {
      throw SourceException(type, 'поток недоступен ($e)');
    }
  }

  Track? _toTrack(Map<String, dynamic> j) {
    if (j['kind'] != null && j['kind'] != 'track') return null;
    final media = j['media'] as Map?;
    final transcodings =
        (media?['transcodings'] as List?)?.cast<Map>() ?? const [];
    String? art = j['artwork_url'] as String?;
    art = art?.replaceAll('-large', '-t500x500');
    return Track(
      id: '${j['id']}',
      title: j['title'] as String? ?? 'Без названия',
      artist: (j['user'] as Map?)?['username'] as String? ?? 'SoundCloud',
      artworkUrl: art,
      duration: j['duration'] != null
          ? Duration(milliseconds: j['duration'] as int)
          : null,
      source: SourceType.soundcloud,
      extra: {'transcodings': transcodings},
    );
  }
}
