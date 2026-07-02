import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../domain/models/playable_stream.dart';
import '../../domain/models/source_type.dart';
import '../../domain/models/track.dart';
import '../../domain/music_source.dart';

/// Источник YouTube Music поверх внутренних эндпоинтов YouTube
/// (как делает NewPipe). Аудио играет ВНУТРИ нашего плеера.
///
/// ⚠️ Нарушает ToS YouTube и может ломаться при их обновлениях.
class YoutubeMusicSource implements MusicSource {
  YoutubeMusicSource(this._dio);

  final Dio _dio;
  final YoutubeExplode _yt = YoutubeExplode();

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  // Музыкальный трек по длительности: ~45 сек … 12 мин.
  static const _minSec = 45;
  static const _maxSec = 720;

  @override
  SourceType get type => SourceType.youtube;

  @override
  Future<bool> get isReady async => true;

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    // Приоритет — поиск YouTube Music (фильтр «Songs»): только музыка, с
    // квадратными обложками альбомов. Если он недоступен — обычный поиск
    // YouTube с фильтром по длительности.
    try {
      final music = await _musicSearch(query, limit: limit);
      if (music.isNotEmpty) return music;
    } catch (_) {/* падаем на обычный поиск */}
    try {
      final results = await _yt.search.search(query);
      return _onlyMusic(results).take(limit).toList();
    } catch (e) {
      throw SourceException(type, 'не удалось выполнить поиск ($e)');
    }
  }

  // --- Поиск через InnerTube music.youtube.com (только музыка) ---

  String? _musicKey;
  String? _musicVer;

  /// Фильтр результатов «Songs» (из ytmusicapi).
  static const _songsParam = 'EgWKAQIIAWoKEAkQBRAKEAMQBA==';

  Future<void> _ensureMusicKeys() async {
    if (_musicKey != null) return;
    final home = await _dio.get<String>('https://music.youtube.com/',
        options: Options(responseType: ResponseType.plain, headers: {
          'User-Agent': _ua,
          'Accept-Language': 'en-US,en;q=0.9',
          'Cookie': 'SOCS=CAI;',
        }));
    final html = home.data ?? '';
    _musicKey =
        RegExp(r'"INNERTUBE_API_KEY":"([^"]+)"').firstMatch(html)?.group(1);
    _musicVer = RegExp(r'"INNERTUBE_CONTEXT_CLIENT_VERSION":"([^"]+)"')
            .firstMatch(html)
            ?.group(1) ??
        '1.20240101.01.00';
  }

  Future<List<Track>> _musicSearch(String query, {int limit = 20}) async {
    await _ensureMusicKeys();
    if (_musicKey == null) return const [];
    final resp = await _dio.post(
      'https://music.youtube.com/youtubei/v1/search',
      queryParameters: {'key': _musicKey},
      data: {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': _musicVer,
            'hl': 'en',
            'gl': 'US',
          }
        },
        'query': query,
        'params': _songsParam,
      },
      options: Options(headers: {
        'User-Agent': _ua,
        'Content-Type': 'application/json',
        'Origin': 'https://music.youtube.com',
        'Referer': 'https://music.youtube.com/',
      }),
    );
    final out = <Track>[];
    final seen = <String>{};
    void walk(dynamic n) {
      if (out.length >= limit) return;
      if (n is Map) {
        final r = n['musicResponsiveListItemRenderer'];
        if (r is Map) {
          final t = _mrlirToTrack(r);
          if (t != null && seen.add(t.id)) out.add(t);
        }
        for (final v in n.values) {
          walk(v);
        }
      } else if (n is List) {
        for (final v in n) {
          walk(v);
        }
      }
    }

    walk(resp.data);
    return out;
  }

  /// Разбирает musicResponsiveListItemRenderer в Track.
  Track? _mrlirToTrack(Map r) {
    final videoId = (_dig(r, ['playlistItemData', 'videoId']) ??
        _dig(r, [
          'overlay',
          'musicItemThumbnailOverlayRenderer',
          'content',
          'musicPlayButtonRenderer',
          'playNavigationEndpoint',
          'watchEndpoint',
          'videoId'
        ]) ??
        _dig(r, [
          'flexColumns',
          0,
          'musicResponsiveListItemFlexColumnRenderer',
          'text',
          'runs',
          0,
          'navigationEndpoint',
          'watchEndpoint',
          'videoId'
        ])) as String?;
    final title = _dig(r, [
      'flexColumns',
      0,
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
      0,
      'text'
    ]) as String?;
    if (videoId == null || title == null) return null;

    var artist = 'YouTube';
    Duration? duration;
    final runs = _dig(r, [
      'flexColumns',
      1,
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs'
    ]);
    if (runs is List && runs.isNotEmpty) {
      artist = (_dig(runs.first, ['text']) ?? 'YouTube').toString();
      duration = _parseClockDuration(_dig(runs.last, ['text'])?.toString());
    }
    const topic = ' - Topic';
    if (artist.endsWith(topic)) {
      artist = artist.substring(0, artist.length - topic.length);
    }

    // Настоящая квадратная обложка альбома (googleusercontent) — если есть,
    // берём её (крупнее), иначе превью видео.
    String? art;
    final thumbs = _dig(
        r, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
    if (thumbs is List && thumbs.isNotEmpty) {
      final url = _dig(thumbs.last, ['url'])?.toString();
      art = url?.replaceAll(RegExp(r'=w\d+-h\d+'), '=w544-h544');
    }
    art ??= ytArtwork(videoId);

    return Track(
      id: videoId,
      title: title,
      artist: artist,
      artworkUrl: art,
      duration: duration,
      source: SourceType.youtube,
    );
  }

  @override
  Future<List<Track>> feed({int limit = 20}) async {
    const seeds = ['Top hits 2025', 'Trending music', 'New music this week'];
    final out = <Track>[];
    for (final s in seeds) {
      try {
        final r = await _yt.search.search(s);
        out.addAll(_onlyMusic(r).take((limit / seeds.length).ceil()));
      } catch (_) {/* пропускаем неудачный сид */}
      if (out.length >= limit) break;
    }
    return out.take(limit).toList();
  }

  @override
  Future<PlayableStream> resolveStream(Track track) async {
    try {
      StreamManifest manifest;
      try {
        // Быстрый путь: только androidVr. Замерено — в 5–6 раз быстрее перебора
        // трёх клиентов (~1.5с против ~14с), и ссылка играбельна: androidVr не
        // троттлит поток, поэтому n-параметр не мешает. requireWatchPage не
        // трогаем (по умолчанию true — нужен для расшифровки).
        manifest = await _yt.videos.streamsClient.getManifest(
          track.id,
          ytClients: [YoutubeApiClient.androidVr],
        );
      } catch (_) {
        // Редкий случай (видео недоступно androidVr) — полный набор клиентов.
        manifest = await _yt.videos.streamsClient.getManifest(
          track.id,
          ytClients: [
            YoutubeApiClient.androidVr,
            YoutubeApiClient.android,
            YoutubeApiClient.ios,
          ],
        );
      }
      final audio = manifest.audioOnly.isNotEmpty
          ? manifest.audioOnly.withHighestBitrate()
          : manifest.muxed.withHighestBitrate();
      return PlayableStream(
        uri: audio.url,
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );
    } catch (e) {
      throw SourceException(type, 'поток недоступен ($e)');
    }
  }

  /// Импорт плейлиста по ссылке/ID. Тянем напрямую из ytInitialData + InnerTube
  /// континуаций (как делает сам сайт YouTube). Разбираем текущую схему
  /// `lockupViewModel` — старая `playlistVideoRenderer` YouTube больше не
  /// отдаёт ни для одного плейлиста (проверено вживую), поэтому парсер должен
  /// идти следом за реальной разметкой, а не за документацией пакета.
  Future<({String title, List<Track> tracks})> importPlaylist(String urlOrId,
      {int limit = 500}) async {
    final m = RegExp(r'list=([A-Za-z0-9_-]+)').firstMatch(urlOrId);
    final id = m?.group(1) ?? urlOrId.trim();

    final page = await _dio.get<String>(
      'https://www.youtube.com/playlist?list=$id',
      options: Options(responseType: ResponseType.plain, headers: {
        'User-Agent': _ua,
        'Accept-Language': 'en-US,en;q=0.9',
      }),
    );
    final html = page.data ?? '';
    final initial = _extractJson(html, 'ytInitialData');
    final apiKey =
        RegExp(r'"INNERTUBE_API_KEY":"([^"]+)"').firstMatch(html)?.group(1);
    final clientVersion = RegExp(r'"INNERTUBE_CONTEXT_CLIENT_VERSION":"([^"]+)"')
            .firstMatch(html)
            ?.group(1) ??
        '2.20240101.00.00';

    final title = (_dig(initial, [
              'header',
              'playlistHeaderRenderer',
              'title',
              'simpleText'
            ]) ??
            _dig(initial, ['metadata', 'playlistMetadataRenderer', 'title']) ??
            'Импортированный плейлист')
        .toString();

    final tracks = <Track>[];
    final seen = <String>{};
    var token = _collect(initial, tracks, seen);

    var guard = 0;
    while (token != null &&
        apiKey != null &&
        tracks.length < limit &&
        guard++ < 60) {
      try {
        final resp = await _dio.post(
          'https://www.youtube.com/youtubei/v1/browse',
          queryParameters: {'key': apiKey},
          data: {
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': clientVersion,
                'hl': 'en',
                'gl': 'US',
              }
            },
            'continuation': token,
          },
          options: Options(headers: {
            'User-Agent': _ua,
            'Content-Type': 'application/json',
          }),
        );
        token = _collect(resp.data, tracks, seen);
      } catch (_) {
        break;
      }
    }

    return (title: title, tracks: tracks.take(limit).toList());
  }

  /// Рекурсивно обходит произвольный JSON-ответ InnerTube, собирая
  /// видео-карточки (`lockupViewModel`) и продолжение (`continuationCommand`).
  /// Не зависит от точного пути вложенности — YouTube меняет его без
  /// предупреждения, а сами ключи узлов остаются относительно стабильными.
  String? _collect(dynamic node, List<Track> out, Set<String> seen) {
    String? token;
    void walk(dynamic n) {
      if (n is Map) {
        final lockup = n['lockupViewModel'];
        if (lockup is Map && lockup['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO') {
          final t = _lockupToTrack(lockup);
          if (t != null && seen.add(t.id)) out.add(t);
        }
        final cc = n['continuationCommand'];
        if (cc is Map && cc['token'] is String) {
          token = cc['token'] as String;
        }
        for (final v in n.values) {
          walk(v);
        }
      } else if (n is List) {
        for (final v in n) {
          walk(v);
        }
      }
    }

    walk(node);
    return token;
  }

  Track? _lockupToTrack(Map lockup) {
    final videoId = lockup['contentId'] as String?;
    final meta = _dig(lockup, ['metadata', 'lockupMetadataViewModel']);
    final title = _dig(meta, ['title', 'content']) as String?;
    if (videoId == null || title == null) return null;

    var artist = (_dig(meta, [
              'metadata',
              'contentMetadataViewModel',
              'metadataRows',
              0,
              'metadataParts',
              0,
              'text',
              'content'
            ]) ??
            '')
        .toString();
    const topic = ' - Topic';
    if (artist.endsWith(topic)) {
      artist = artist.substring(0, artist.length - topic.length);
    }

    Duration? duration;
    final overlays =
        _dig(lockup, ['contentImage', 'thumbnailViewModel', 'overlays']);
    if (overlays is List) {
      for (final o in overlays) {
        final badges = _dig(
            o, ['thumbnailBottomOverlayViewModel', 'badges']);
        if (badges is List) {
          for (final b in badges) {
            final text = _dig(b, ['thumbnailBadgeViewModel', 'text']);
            final d = _parseClockDuration(text?.toString());
            if (d != null) duration = d;
          }
        }
      }
    }

    return Track(
      id: videoId,
      title: title,
      artist: artist.isEmpty ? 'YouTube' : artist,
      artworkUrl: ytArtwork(videoId),
      duration: duration,
      source: SourceType.youtube,
    );
  }

  /// Парсит длительность вида «1:02:07» / «2:07» в Duration.
  Duration? _parseClockDuration(String? s) {
    if (s == null || !RegExp(r'^\d{1,2}(:\d{2}){1,2}$').hasMatch(s)) {
      return null;
    }
    final parts = s.split(':').map(int.parse).toList();
    var seconds = 0;
    for (final p in parts) {
      seconds = seconds * 60 + p;
    }
    return Duration(seconds: seconds);
  }

  /// Достаёт JSON-объект из inline-скрипта (например, ytInitialData) с учётом
  /// строк и экранирования.
  Map<String, dynamic> _extractJson(String html, String marker) {
    var i = html.indexOf(marker);
    if (i < 0) return const {};
    i = html.indexOf('{', i);
    if (i < 0) return const {};
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var j = i; j < html.length; j++) {
      final c = html[j];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
      } else {
        if (c == '"') {
          inStr = true;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) {
            try {
              return jsonDecode(html.substring(i, j + 1))
                  as Map<String, dynamic>;
            } catch (_) {
              return const {};
            }
          }
        }
      }
    }
    return const {};
  }

  dynamic _dig(dynamic node, List<dynamic> path) {
    for (final p in path) {
      if (node == null) return null;
      if (p is int) {
        if (node is List && p >= 0 && p < node.length) {
          node = node[p];
        } else {
          return null;
        }
      } else {
        if (node is Map) {
          node = node[p];
        } else {
          return null;
        }
      }
    }
    return node;
  }

  /// Оставляем только похожее на музыкальный трек: не прямой эфир и длительность
  /// в окне песни. Это убирает обычные видео, эфиры, миксы и подкасты.
  Iterable<Track> _onlyMusic(Iterable<Video> videos) {
    return videos.where((v) {
      if (v.isLive) return false;
      final d = v.duration;
      if (d == null) return false;
      final s = d.inSeconds;
      return s >= _minSec && s <= _maxSec;
    }).map(_videoToTrack);
  }

  Track _videoToTrack(Video v) {
    var artist = v.author;
    // YouTube Music помечает авто-каналы артистов как «Имя - Topic».
    const topic = ' - Topic';
    if (artist.endsWith(topic)) {
      artist = artist.substring(0, artist.length - topic.length);
    }
    return Track(
      id: v.id.value,
      title: v.title,
      artist: artist,
      // Единый формат превью (4:3 с полосами) — их обрезает Artwork в квадрат.
      artworkUrl: ytArtwork(v.id.value),
      duration: v.duration,
      source: SourceType.youtube,
    );
  }

  /// URL превью YouTube по videoId. hqdefault есть всегда; чёрные полосы 4:3
  /// убираются зум-кропом в [Artwork].
  static String ytArtwork(String videoId) =>
      'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

  void dispose() => _yt.close();
}
