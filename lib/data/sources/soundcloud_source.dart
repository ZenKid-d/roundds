import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/diagnostics.dart';
import '../../domain/constants.dart';
import '../../domain/models/artist_profile.dart';
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
  SoundcloudSource(this._dio, {String? cachedClientId, String? token})
      : _clientId = cachedClientId,
        _oauthToken = token;

  final Dio _dio;
  String? _clientId;
  String? _oauthToken;

  static const _apiBase = 'https://api-v2.soundcloud.com';

  /// OAuth-токен аккаунта. С подпиской Go+ открывает полные потоки треков,
  /// которые покрыты подпиской пользователя (легитимный доступ к оплаченному).
  void setToken(String? token) => _oauthToken = token;
  bool get hasToken => (_oauthToken ?? '').isNotEmpty;

  Map<String, dynamic> get _authHeaders =>
      hasToken ? {'Authorization': 'OAuth $_oauthToken'} : const {};

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
    Diagnostics.instance
        .error('sc.clientId', 'не найден client_id в ${scripts.length} скриптах');
    throw SourceException(type, 'не удалось получить client_id');
  }

  Future<void> _ensureClientId() async {
    if (_clientId == null) await refreshClientId();
  }

  @override
  bool get supportsPaging => true;

  @override
  Future<List<Track>> search(String query, {int limit = 20, int page = 0}) async {
    await _ensureClientId();
    try {
      final r = await _dio.get('$_apiBase/search/tracks',
          queryParameters: {
            'q': query,
            'client_id': _clientId,
            'limit': limit,
            if (page > 0) 'offset': page * limit,
          },
          options: Options(headers: _authHeaders));
      final list = (r.data['collection'] as List? ?? []);
      return list
          .whereType<Map>()
          .map((e) => toTrack(e.cast<String, dynamic>()))
          .where((t) => t != null)
          .cast<Track>()
          .toList();
    } catch (e) {
      // Сетевой сбой источника не фатален — агрегатор деградирует мягко.
      Diagnostics.instance.warn('sc.search', '«$query»: $e');
      throw SourceException(type, 'ошибка поиска ($e)');
    }
  }

  @override
  Future<List<Track>> feed({int limit = 20}) async {
    await _ensureClientId();
    // «Лента» — популярное в основных жанрах за неделю.
    try {
      final r = await _dio.get('$_apiBase/charts',
          queryParameters: {
            'kind': 'top',
            'genre': 'soundcloud:genres:all-music',
            'client_id': _clientId,
            'limit': limit,
          },
          options: Options(headers: _authHeaders));
      final list = (r.data['collection'] as List? ?? []);
      return list
          .map((e) => (e as Map)['track'])
          .whereType<Map>()
          .map((e) => toTrack(e.cast<String, dynamic>()))
          .where((t) => t != null)
          .cast<Track>()
          .toList();
    } catch (_) {
      // fallback на поиск, если charts недоступны
      return search('trending', limit: limit);
    }
  }

  /// Похожие/связанные треки (для рекомендаций и радио).
  Future<List<Track>> related(String trackId, {int limit = 20}) async {
    await _ensureClientId();
    try {
      final r = await _dio.get('$_apiBase/tracks/$trackId/related',
          queryParameters: {'client_id': _clientId, 'limit': limit},
          options: Options(headers: _authHeaders));
      final list = (r.data['collection'] as List? ?? []);
      return list
          .whereType<Map>()
          .map((e) => toTrack(e.cast<String, dynamic>()))
          .whereType<Track>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<PlayableStream> resolveStream(Track track) async {
    await _ensureClientId();
    final transcodings =
        (track.extra['transcodings'] as List?)?.cast<Map>() ?? const [];
    if (transcodings.isEmpty) {
      throw SourceException(type, 'нет доступного потока для трека');
    }
    // progressive (mp3) надёжнее всего; hls тоже играбелен в ExoPlayer.
    int rank(Map t) {
      final p = t['format']?['protocol'];
      if (p == 'progressive') return 0;
      if (p == 'hls') return 1;
      return 2;
    }

    final ordered = [...transcodings]..sort((a, b) => rank(a) - rank(b));
    for (final t in ordered) {
      final url = t['url'] as String?;
      if (url == null) continue;
      try {
        final r = await _dio.get(url,
            queryParameters: {'client_id': _clientId},
            options: Options(headers: _authHeaders));
        final streamUrl = (r.data as Map)['url'] as String?;
        if (streamUrl != null && streamUrl.isNotEmpty) {
          return PlayableStream(
            uri: Uri.parse(streamUrl),
            expiresAt: DateTime.now().add(defaultStreamExpiry),
          );
        }
      } catch (_) {/* пробуем следующий транскодинг */}
    }
    Diagnostics.instance.error('sc.resolve',
        '${track.id} «${track.title}»: нет играбельного транскодинга');
    throw SourceException(
      type,
      'поток недоступен — возможно, трек доступен только по подписке SoundCloud Go.',
    );
  }

  // Нативной загрузки нет — грузим по resolveStream-URL (см. DownloadsController).
  @override
  Future<bool> downloadTo(Track track, String path,
          {void Function(int received, int total)? onProgress}) async =>
      false;

  @visibleForTesting
  static Track? toTrack(Map<String, dynamic> j) {
    if (j['kind'] != null && j['kind'] != 'track') return null;
    final media = j['media'] as Map?;
    final transcodings =
        (media?['transcodings'] as List?)?.cast<Map>() ?? const [];
    final user = j['user'] as Map?;
    String? art = j['artwork_url'] as String?;
    art = art?.replaceAll('-large', '-t500x500');
    return Track(
      id: '${j['id']}',
      title: j['title'] as String? ?? 'Без названия',
      artist: user?['username'] as String? ?? 'SoundCloud',
      artworkUrl: art,
      duration: j['duration'] != null
          ? Duration(milliseconds: j['duration'] as int)
          : null,
      source: SourceType.soundcloud,
      extra: {
        'transcodings': transcodings,
        // id автора трека — нужен для запроса полного профиля (страница
        // исполнителя: аватар/баннер/подписчики), см. artistProfile().
        if (user?['id'] != null) 'scUserId': user!['id'],
      },
    );
  }

  /// Профиль автора трека [seed] (аватар/баннер/био/подписчики) —
  /// для страницы исполнителя. null, если у трека нет id автора (сток-данные
  /// без user), либо запрос не удался.
  Future<ArtistProfile?> artistProfile(Track seed) async {
    final userId = seed.extra['scUserId'];
    if (userId == null) return null;
    await _ensureClientId();
    try {
      final r = await _dio.get('$_apiBase/users/$userId',
          queryParameters: {'client_id': _clientId},
          options: Options(headers: _authHeaders));
      final j = (r.data as Map).cast<String, dynamic>();
      final visuals = (j['visuals'] as Map?)?['visuals'] as List?;
      String? banner;
      if (visuals != null && visuals.isNotEmpty) {
        banner = (visuals.first as Map?)?['visual_url'] as String?;
      }
      final bio = (j['description'] as String?)?.trim();
      return ArtistProfile(
        name: j['username'] as String? ?? seed.artist,
        source: SourceType.soundcloud,
        avatarUrl:
            (j['avatar_url'] as String?)?.replaceAll('-large', '-t500x500'),
        bannerUrl: banner,
        bio: (bio == null || bio.isEmpty) ? null : bio,
        followers: (j['followers_count'] as num?)?.toInt(),
      );
    } catch (e) {
      Diagnostics.instance.warn('sc.artistProfile', '$userId: $e');
      return null;
    }
  }
}
