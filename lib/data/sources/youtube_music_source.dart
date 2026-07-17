import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/diagnostics.dart';
import '../../domain/models/playable_stream.dart';
import '../../domain/models/source_type.dart';
import '../../domain/models/track.dart';
import '../../domain/music_source.dart';

/// Источник YouTube Music поверх внутренних эндпоинтов YouTube
/// (как делает NewPipe). Аудио играет ВНУТРИ нашего плеера.
///
/// ⚠️ Нарушает ToS YouTube и может ломаться при их обновлениях.
class YoutubeMusicSource implements MusicSource {
  /// [yt] можно передать заранее собранным (напр. с DoH-клиентом для обхода
  /// блокировок); по умолчанию — обычный [YoutubeExplode].
  YoutubeMusicSource(this._dio, {YoutubeExplode? yt})
      : _yt = yt ?? YoutubeExplode();

  final Dio _dio;
  final YoutubeExplode _yt;

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  // Музыкальный трек по длительности: ~45 сек … 12 мин.
  static const _minSec = 45;
  static const _maxSec = 720;

  /// Качество потока/загрузки: 0 — низкое, 1 — среднее, 2 — высокое.
  int streamQuality = 2;

  /// Достоверный музыкальный признак канала-загрузчика: авто-канал YouTube
  /// «<Артист> - Topic» (Art Track лицензированной музыки) или VEVO. Без
  /// официального Data API это единственный надёжный маркер «трек, а не обычное
  /// видео» (влог/геймплей/подкаст/стрим на такой канал не попадают).
  static bool isMusicUploader(String? uploader) {
    final u = (uploader ?? '').toLowerCase();
    return u.contains('- topic') || u.contains('vevo');
  }

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
    } catch (e) {
      Diagnostics.instance
          .info('yt.search', 'InnerTube fell back to plain search: $e');
    }
    try {
      final results = await _yt.search.search(query);
      return _onlyMusic(results).take(limit).toList();
    } catch (e) {
      // Сетевой сбой источника не фатален — агрегатор деградирует мягко.
      Diagnostics.instance.warn('yt.search', '«$query»: $e');
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
    // Сначала строгий фильтр «Songs» — только лицензионные треки с чистой
    // атрибуцией. Но YouTube периодически ломает токен фильтра или не отдаёт
    // «песни» для части регионов/без входа — тогда ответ пустой («No results»),
    // и раньше поиск молча падал в обычный видео-поиск, полный каверов. Если
    // фильтр пуст — повторяем БЕЗ него и разбираем «Top result» + музыкальные
    // видео, чтобы официальный релиз всё равно нашёлся.
    final songs = await _musicSearchRequest(query, limit: limit, songs: true);
    if (songs.isNotEmpty) return songs;
    return _musicSearchRequest(query, limit: limit, songs: false);
  }

  Future<List<Track>> _musicSearchRequest(String query,
      {required int limit, required bool songs}) async {
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
        if (songs) 'params': _songsParam,
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
        // «Top result» — самый релевантный трек (часто именно официальный),
        // лежит в карточке, а не в списке; парсер списка её пропускал.
        final card = n['musicCardShelfRenderer'];
        if (card is Map) {
          final t = cardShelfToTrack(card);
          if (t != null && seen.add(t.id)) out.add(t);
        }
        final r = n['musicResponsiveListItemRenderer'];
        if (r is Map) {
          final t = mrlirToTrack(r);
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

  // Типы элементов в подписи нефильтрованной выдачи YT Music (первый ран):
  // «Song»/«Video» — музыка, оставляем; «Episode»/«Podcast»/«Profile»/«Show»
  // — не музыка (но с videoId), отсекаем.
  static const _rowTypes = {
    'song', 'video', 'artist', 'album', 'single', 'ep', 'playlist',
    'episode', 'profile', 'podcast', 'show',
  };
  static const _skipTypes = {'episode', 'podcast', 'profile', 'show'};

  static bool _looksLikeStat(String s) {
    final l = s.toLowerCase();
    return l.contains('view') ||
        l.contains('monthly') ||
        l.contains('plays') ||
        l.contains('subscriber');
  }

  /// Разбирает ряд подписи под названием в (тип, артист, длительность).
  /// Фильтр «Songs» даёт «Артист • Альбом • 3:21» (типа нет), а нефильтрованная
  /// выдача — «Video • Канал • 3.2M views • 6:07»: первый ран это ТИП элемента,
  /// и раньше он ошибочно попадал в артиста («Video»). Разделители « • » и
  /// счётчики просмотров/аудитории пропускаем.
  @visibleForTesting
  static ({String? type, String artist, Duration? duration}) metaFromRuns(
      List runs) {
    final texts = <String>[];
    for (final run in runs) {
      final t = (dig(run, ['text']) ?? '').toString().trim();
      if (t.isEmpty || t == '•') continue;
      texts.add(t);
    }
    Duration? duration;
    for (final t in texts) {
      final d = parseClockDuration(t);
      if (d != null) duration = d;
    }
    String? type;
    var i = 0;
    if (texts.isNotEmpty && _rowTypes.contains(texts.first.toLowerCase())) {
      type = texts.first.toLowerCase();
      i = 1;
    }
    var artist = 'YouTube';
    for (; i < texts.length; i++) {
      final t = texts[i];
      if (parseClockDuration(t) != null || _looksLikeStat(t)) continue;
      artist = t;
      break;
    }
    return (type: type, artist: artist, duration: duration);
  }

  /// «Top result» YT Music — самый релевантный результат (обычно официальный
  /// трек/клип). Лежит в отдельной карточке, а не в списке, поэтому раньше
  /// терялся, а в выдаче оставались только каверы из списка. Название и videoId
  /// — в title.runs, артист/длительность — в subtitle.runs.
  @visibleForTesting
  static Track? cardShelfToTrack(Map card) {
    final titleRun = dig(card, ['title', 'runs', 0]);
    final videoId =
        dig(titleRun, ['navigationEndpoint', 'watchEndpoint', 'videoId'])
            as String?;
    final title = dig(titleRun, ['text']) as String?;
    if (videoId == null || title == null) return null;
    final subruns = dig(card, ['subtitle', 'runs']);
    final meta = metaFromRuns(subruns is List ? subruns : const []);
    var artist = meta.artist;
    const topic = ' - Topic';
    if (artist.endsWith(topic)) {
      artist = artist.substring(0, artist.length - topic.length);
    }
    String? art;
    final thumbs = dig(card,
        ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
    if (thumbs is List && thumbs.isNotEmpty) {
      final url = dig(thumbs.last, ['url'])?.toString();
      art = url?.replaceAll(RegExp(r'=w\d+-h\d+'), '=w720-h720');
    }
    art ??= ytArtwork(videoId);
    return Track(
      id: videoId,
      title: title,
      artist: artist,
      artworkUrl: art,
      duration: meta.duration,
      source: SourceType.youtube,
    );
  }

  /// Разбирает musicResponsiveListItemRenderer в Track.
  @visibleForTesting
  static Track? mrlirToTrack(Map r) {
    final videoId = (dig(r, ['playlistItemData', 'videoId']) ??
        dig(r, [
          'overlay',
          'musicItemThumbnailOverlayRenderer',
          'content',
          'musicPlayButtonRenderer',
          'playNavigationEndpoint',
          'watchEndpoint',
          'videoId'
        ]) ??
        dig(r, [
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
    final title = dig(r, [
      'flexColumns',
      0,
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs',
      0,
      'text'
    ]) as String?;
    if (videoId == null || title == null) return null;

    final runs = dig(r, [
      'flexColumns',
      1,
      'musicResponsiveListItemFlexColumnRenderer',
      'text',
      'runs'
    ]);
    final meta = metaFromRuns(runs is List ? runs : const []);
    // Нефильтрованная выдача мешает песни/видео с эпизодами подкастов и
    // профилями — у них тоже есть videoId, но это не музыка. Отсекаем по типу.
    if (_skipTypes.contains(meta.type)) return null;
    var artist = meta.artist;
    final duration = meta.duration;
    const topic = ' - Topic';
    if (artist.endsWith(topic)) {
      artist = artist.substring(0, artist.length - topic.length);
    }

    // Настоящая квадратная обложка альбома (googleusercontent) — если есть,
    // берём её (крупнее), иначе превью видео.
    String? art;
    final thumbs = dig(
        r, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
    if (thumbs is List && thumbs.isNotEmpty) {
      final url = dig(thumbs.last, ['url'])?.toString();
      art = url?.replaceAll(RegExp(r'=w\d+-h\d+'), '=w720-h720');
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
    final per = (limit / seeds.length).ceil();
    for (final s in seeds) {
      try {
        out.addAll(await search(s, limit: per));
      } catch (_) {/* пропускаем неудачный сид */}
      if (out.length >= limit) break;
    }
    return out.take(limit).toList();
  }

  // Кэш резолва по videoId — реже дёргаем YouTube (меньше шанс поймать
  // лимит) при повторах: реплей, предзагрузка, радио с возвратами. Отдаём, пока
  // ссылка не истекла. Сбрасывается при ошибке воспроизведения (evictStreamCache),
  // чтобы авто-перерезолв в плеере всегда брал свежую ссылку, а не битую из кэша.
  final Map<String, PlayableStream> _streamCache = {};

  void evictStreamCache(String videoId) => _streamCache.remove(videoId);

  @override
  Future<PlayableStream> resolveStream(Track track) async {
    final cached = _streamCache[track.id];
    if (cached != null && !cached.isExpired) return cached;
    final s = await _resolveStreamUncached(track);
    _streamCache[track.id] = s;
    if (_streamCache.length > 128) {
      _streamCache.remove(_streamCache.keys.first);
    }
    return s;
  }

  Future<PlayableStream> _resolveStreamUncached(Track track) async {
    try {
      final info = await _selectStream(track.id);
      if (info == null) {
        throw SourceException(type, 'нет аудио-дорожки');
      }
      return PlayableStream(
        uri: info.url,
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );
    } catch (e) {
      Diagnostics.instance
          .error('yt.resolve', '${track.id} «${track.title}»: $e');
      throw SourceException(type, 'поток недоступен ($e)');
    }
  }

  // Клиенты для «широкого» перебора, когда быстрый androidVr не дал поток.
  // androidVr/android/ios всё чаще получают от YouTube playabilityStatus=ERROR
  // «This video is not available» (VideoUnplayableException) на вполне обычных
  // треках. tv и mediaConnect ходят как встраиваемый/медиа-клиент и обходят
  // эти региональные/возрастные ограничения, androidMusic заточен под музыку.
  // Порядок — от самых устойчивых к резервным; getManifest сливает потоки со
  // всех клиентов и бросает, только если поток не дал НИ ОДИН.
  static final List<YoutubeApiClient> _fallbackClients = [
    YoutubeApiClient.androidVr,
    YoutubeApiClient.tv,
    YoutubeApiClient.mediaConnect,
    YoutubeApiClient.androidMusic,
    YoutubeApiClient.android,
    YoutubeApiClient.ios,
  ];

  /// Выбирает подходящий поток (audio-only по качеству; иначе лучший muxed).
  /// Общий код для проигрывания (нужен URL) и загрузки (нужен StreamInfo).
  Future<StreamInfo?> _selectStream(String videoId) async {
    // Быстрый путь: только androidVr. Замерено — в 5–6 раз быстрее перебора
    // нескольких клиентов (~1.5с против ~14с).
    //
    // requireWatchPage НЕ трогаем (по умолчанию true): страница /watch нужна,
    // чтобы библиотека расшифровала подпись/n-параметр ссылки. Без неё резолв
    // формально «успешен», но googlevideo отдаёт плееру 403/троттлит — ExoPlayer
    // падает с «Source error» (регресс 96c0bf7, где ставили false ради лимитов).
    // Играбельность важнее редкого rate-limit, поэтому дешифруем как в 2.1.2.
    try {
      final fast = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.androidVr],
      );
      final picked = _pickStream(fast);
      if (picked != null) return picked;
      // androidVr вернул манифест без пригодного аудио — добираем широким
      // набором (ниже), а не сдаёмся: у tv/mediaConnect дорожки могут быть.
    } catch (_) {
      // androidVr отдал «видео недоступно» / упал — идём широким набором.
    }
    final manifest = await _yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: _fallbackClients,
    );
    return _pickStream(manifest);
  }

  /// Из манифеста выбирает audio-only по качеству, иначе лучший muxed.
  StreamInfo? _pickStream(StreamManifest manifest) {
    if (manifest.audioOnly.isNotEmpty) {
      final list = manifest.audioOnly.toList()
        ..sort((a, b) =>
            a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
      // По качеству: низкое — первый, среднее — середина, высокое — последний.
      return streamQuality == 0
          ? list.first
          : streamQuality == 1
              ? list[list.length ~/ 2]
              : list.last;
    }
    if (manifest.muxed.isNotEmpty) return manifest.muxed.withHighestBitrate();
    return null;
  }

  /// Нативная потоковая загрузка через youtube_explode: сам качает аудио
  /// чанками с корректными заголовками. Простой HTTP-GET по googlevideo-ссылке
  /// часто отдаёт 403 (плеер играет ranged-стримингом, а полный GET — нет),
  /// поэтому для скачивания YouTube этот путь надёжнее.
  @override
  Future<bool> downloadTo(
    Track track,
    String path, {
    void Function(int received, int total)? onProgress,
  }) async {
    IOSink? sink;
    try {
      final info = await _selectStream(track.id);
      if (info == null) return false;
      final total = info.size.totalBytes;
      sink = File(path).openWrite();
      var received = 0;
      await for (final chunk in _yt.videos.streamsClient.get(info)) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return true;
    } catch (_) {
      // Не смогли — подчистим частичный файл и отдадим управление dio-пути.
      try {
        await sink?.close();
      } catch (_) {}
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      return false;
    }
  }

  /// Похожие треки (радио) для YouTube-трека через InnerTube `next`. Это
  /// настоящая авто-очередь YouTube Music, а не подбор по артисту.
  Future<List<Track>> relatedTo(String videoId, {int limit = 40}) async {
    await _ensureMusicKeys();
    if (_musicKey == null) return const [];
    final resp = await _dio.post(
      'https://music.youtube.com/youtubei/v1/next',
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
        'enablePersistentPlaylistPanel': true,
        'isAudioOnly': true,
        'videoId': videoId,
        'playlistId': 'RDAMVM$videoId',
      },
      options: Options(headers: {
        'User-Agent': _ua,
        'Content-Type': 'application/json',
        'Origin': 'https://music.youtube.com',
        'Referer': 'https://music.youtube.com/',
      }),
    );
    final out = <Track>[];
    final seen = <String>{videoId}; // сам сид не добавляем
    void walk(dynamic n) {
      if (out.length >= limit) return;
      if (n is Map) {
        final r = n['playlistPanelVideoRenderer'];
        if (r is Map) {
          final t = panelToTrack(r);
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
    // InnerTube-радио изредка подмешивает не-треки (шортсы/длинные миксы) —
    // чистим по окну длительности музыкального трека (покрывает и «Волну»,
    // и ряды «Похожее»).
    return out.where(_looksLikeTrack).toList();
  }

  /// Похоже на трек по длительности (не шортс/не длинный микс-стрим).
  /// Неизвестную длительность оставляем — из радио она приходит не всегда.
  static bool _looksLikeTrack(Track t) {
    final s = t.duration?.inSeconds;
    return s == null || (s >= _minSec && s <= _maxSec);
  }

  @visibleForTesting
  static Track? panelToTrack(Map r) {
    final videoId = dig(r, ['videoId']) as String?;
    final title = dig(r, ['title', 'runs', 0, 'text']) as String?;
    if (videoId == null || title == null) return null;
    var artist =
        (dig(r, ['longBylineText', 'runs', 0, 'text']) ?? 'YouTube').toString();
    const topic = ' - Topic';
    if (artist.endsWith(topic)) {
      artist = artist.substring(0, artist.length - topic.length);
    }
    final duration =
        parseClockDuration(dig(r, ['lengthText', 'runs', 0, 'text'])?.toString());
    return Track(
      id: videoId,
      title: title,
      artist: artist,
      artworkUrl: ytArtwork(videoId),
      duration: duration,
      source: SourceType.youtube,
    );
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
    final initial = extractJson(html, 'ytInitialData');
    final apiKey =
        RegExp(r'"INNERTUBE_API_KEY":"([^"]+)"').firstMatch(html)?.group(1);
    final clientVersion = RegExp(r'"INNERTUBE_CONTEXT_CLIENT_VERSION":"([^"]+)"')
            .firstMatch(html)
            ?.group(1) ??
        '2.20240101.00.00';

    final title = (dig(initial, [
              'header',
              'playlistHeaderRenderer',
              'title',
              'simpleText'
            ]) ??
            dig(initial, ['metadata', 'playlistMetadataRenderer', 'title']) ??
            'Импортированный плейлист')
        .toString();

    final tracks = <Track>[];
    final seen = <String>{};
    var token = collect(initial, tracks, seen);

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
        token = collect(resp.data, tracks, seen);
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
  @visibleForTesting
  static String? collect(dynamic node, List<Track> out, Set<String> seen) {
    String? token;
    void walk(dynamic n) {
      if (n is Map) {
        final lockup = n['lockupViewModel'];
        if (lockup is Map && lockup['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO') {
          final t = lockupToTrack(lockup);
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

  @visibleForTesting
  static Track? lockupToTrack(Map lockup) {
    final videoId = lockup['contentId'] as String?;
    final meta = dig(lockup, ['metadata', 'lockupMetadataViewModel']);
    final title = dig(meta, ['title', 'content']) as String?;
    if (videoId == null || title == null) return null;

    var artist = (dig(meta, [
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
        dig(lockup, ['contentImage', 'thumbnailViewModel', 'overlays']);
    if (overlays is List) {
      for (final o in overlays) {
        final badges = dig(
            o, ['thumbnailBottomOverlayViewModel', 'badges']);
        if (badges is List) {
          for (final b in badges) {
            final text = dig(b, ['thumbnailBadgeViewModel', 'text']);
            final d = parseClockDuration(text?.toString());
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
  @visibleForTesting
  static Duration? parseClockDuration(String? s) {
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
  @visibleForTesting
  static Map<String, dynamic> extractJson(String html, String marker) {
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

  @visibleForTesting
  static dynamic dig(dynamic node, List<dynamic> path) {
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

  /// Оставляем только музыкальный трек: с музыкального канала («- Topic»/VEVO),
  /// не прямой эфир и длительность в окне песни. Проверка канала обязательна —
  /// плоский поиск YouTube иначе вернёт обычные видео (влоги/геймплей/ролики).
  /// Канал проверяем ДО [_videoToTrack] — он срезает « - Topic» из имени.
  Iterable<Track> _onlyMusic(Iterable<Video> videos) {
    return videos.where((v) {
      if (v.isLive) return false;
      if (!isMusicUploader(v.author)) return false; // не обычные видео
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

  /// URL превью YouTube по videoId. sddefault (640×480) заметно чётче
  /// hqdefault и почти всегда доступен; та же геометрия 4:3 — чёрные полосы
  /// убираются зум-кропом в [Artwork].
  static String ytArtwork(String videoId) =>
      'https://i.ytimg.com/vi/$videoId/sddefault.jpg';

  void dispose() => _yt.close();
}
