import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/diagnostics.dart';
import '../../domain/models/playable_stream.dart';
import '../../domain/models/source_type.dart';
import '../../domain/models/track.dart';
import '../../domain/music_source.dart';

/// Источник Яндекс Музыки поверх неофициального API.
/// Требует OAuth-токен пользователя. Аудио играет ВНУТРИ нашего плеера
/// (прямой mp3 по подписанной ссылке).
///
/// ⚠️ Самый хрупкий источник: нарушает ToS, риск блокировки аккаунта,
/// схема подписи может измениться.
class YandexSource implements MusicSource {
  YandexSource(this._dio, {String? token}) : _token = token;

  final Dio _dio;
  String? _token;

  static const _base = 'https://api.music.yandex.net';
  // Соль для подписи download-info (публично известная).
  static const _signSalt = 'XGRlBW9FXlekgbPrRHuSiA';

  @override
  SourceType get type => SourceType.yandex;

  int? _uid;

  void setToken(String? token) {
    _token = token;
    _uid = null;
  }

  Future<int> _ensureUid() async {
    if (_uid != null) return _uid!;
    final r = await _dio.get('$_base/account/status', options: _opts);
    _uid = (r.data['result']?['account']?['uid'] as num).toInt();
    return _uid!;
  }

  /// Список плейлистов пользователя (для импорта).
  Future<List<({int kind, String title, int count})>> userPlaylists() async {
    _requireToken();
    final uid = await _ensureUid();
    final r =
        await _dio.get('$_base/users/$uid/playlists/list', options: _opts);
    final list = (r.data['result'] as List? ?? []);
    return list
        .whereType<Map>()
        .map((e) => (
              kind: (e['kind'] as num).toInt(),
              title: e['title'] as String? ?? 'Плейлист',
              count: (e['trackCount'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  /// Треки плейлиста пользователя по его kind.
  Future<List<Track>> playlistTracks(int kind) async {
    _requireToken();
    final uid = await _ensureUid();
    final r =
        await _dio.get('$_base/users/$uid/playlists/$kind', options: _opts);
    final tracks = (r.data['result']?['tracks'] as List? ?? []);
    return tracks
        .map((e) => (e as Map)['track'])
        .whereType<Map>()
        .map((e) => toTrack(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<bool> get isReady async => _token != null && _token!.isNotEmpty;

  Options get _opts => Options(headers: {
        'Authorization': 'OAuth $_token',
        'X-Yandex-Music-Client': 'YandexMusicAndroid/24023621',
      });

  @override
  Future<List<Track>> search(String query, {int limit = 20, int page = 0}) async {
    _requireToken();
    try {
      // ВАЖНО: 'page' раньше был захардкожен в 0 — при догрузке следующей
      // порции (см. поиск) это значило, что API всегда отдавал одну и ту же
      // первую страницу, а вырос бы только клиентский .take(limit); реальных
      // новых треков со второй и последующих страниц не приходило никогда.
      final r = await _dio.get('$_base/search',
          queryParameters: {'text': query, 'type': 'track', 'page': page},
          options: _opts);
      final results =
          (r.data['result']?['tracks']?['results'] as List? ?? []);
      return results
          .whereType<Map>()
          .take(limit)
          .map((e) => toTrack(e.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      // Сетевой сбой источника не фатален — агрегатор деградирует мягко.
      Diagnostics.instance.warn('ya.search', '«$query»: $e');
      throw SourceException(type, 'ошибка поиска ($e)');
    }
  }

  @override
  Future<List<Track>> feed({int limit = 20}) async {
    _requireToken();
    try {
      final r = await _dio.get('$_base/landing3',
          queryParameters: {'blocks': 'chart'}, options: _opts);
      final blocks = (r.data['result']?['blocks'] as List? ?? []);
      for (final b in blocks) {
        if ((b as Map)['type'] == 'chart') {
          final entities = (b['entities'] as List? ?? []);
          return entities
              .map((e) => (e as Map)['data']?['track'])
              .whereType<Map>()
              .take(limit)
              .map((e) => toTrack(e.cast<String, dynamic>()))
              .toList();
        }
      }
      return const [];
    } catch (e) {
      Diagnostics.instance.warn('ya.feed', 'chart: $e');
      return const [];
    }
  }

  /// Похожие треки (для рекомендаций и радио).
  Future<List<Track>> similar(String trackId, {int limit = 30}) async {
    if (_token == null || _token!.isEmpty) return const [];
    try {
      final r =
          await _dio.get('$_base/tracks/$trackId/similar', options: _opts);
      final list = (r.data['result']?['similarTracks'] as List? ?? []);
      return list
          .whereType<Map>()
          .take(limit)
          .map((e) => toTrack(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<PlayableStream> resolveStream(Track track) async {
    _requireToken();
    try {
      final info = await _dio.get('$_base/tracks/${track.id}/download-info',
          options: _opts);
      final variants = (info.data['result'] as List? ?? []);
      if (variants.isEmpty) {
        throw SourceException(type, 'нет вариантов загрузки');
      }
      // Берём mp3 с наибольшим битрейтом.
      variants.sort((a, b) =>
          ((b['bitrateInKbps'] ?? 0) as int) -
          ((a['bitrateInKbps'] ?? 0) as int));
      final best = variants.firstWhere(
        (v) => (v as Map)['codec'] == 'mp3',
        orElse: () => variants.first,
      ) as Map;

      final xmlResp = await _dio.get<String>(best['downloadInfoUrl'] as String,
          options: Options(responseType: ResponseType.plain));
      final xml = xmlResp.data ?? '';
      final url = buildStreamUrl(
        host: tag(xml, 'host'),
        path: tag(xml, 'path'),
        ts: tag(xml, 'ts'),
        s: tag(xml, 's'),
      );
      return PlayableStream(
        uri: Uri.parse(url),
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );
    } on SourceException {
      rethrow;
    } catch (e) {
      Diagnostics.instance
          .error('ya.resolve', '${track.id} «${track.title}»: $e');
      throw SourceException(type, 'поток недоступен ($e)');
    }
  }

  /// Собирает подписанную mp3-ссылку из полей download-info XML. Схема подписи
  /// (md5 соли+пути+s) — самая хрупкая часть Яндекса, вынесена для тестов.
  @visibleForTesting
  static String buildStreamUrl({
    required String host,
    required String path,
    required String ts,
    required String s,
  }) {
    final sign =
        md5.convert('$_signSalt${path.substring(1)}$s'.codeUnits).toString();
    return 'https://$host/get-mp3/$sign/$ts$path';
  }

  @visibleForTesting
  static String tag(String xml, String tag) {
    final m = RegExp('<$tag>(.*?)</$tag>').firstMatch(xml);
    return m?.group(1) ?? '';
  }

  // Нативной загрузки нет — Яндекс отдаёт прямой mp3, грузится обычным GET.
  @override
  Future<bool> downloadTo(Track track, String path,
          {void Function(int received, int total)? onProgress}) async =>
      false;

  @visibleForTesting
  static Track toTrack(Map<String, dynamic> j) {
    final artists = (j['artists'] as List? ?? [])
        .map((a) => (a as Map)['name'])
        .whereType<String>()
        .join(', ');
    final albums = (j['albums'] as List? ?? []);
    final firstAlbum = albums.isNotEmpty ? albums.first as Map : null;
    String? cover =
        j['coverUri'] as String? ?? firstAlbum?['coverUri'] as String?;
    if (cover != null) cover = 'https://${cover.replaceAll('%%', '400x400')}';
    // albumId кладём в extra — по нему открывается страница альбома (треклист).
    final albumId = firstAlbum?['id'];
    return Track(
      id: '${j['id'] ?? j['realId']}',
      title: j['title'] as String? ?? 'Без названия',
      artist: artists.isEmpty ? 'Яндекс Музыка' : artists,
      album: firstAlbum?['title'] as String?,
      artworkUrl: cover,
      duration: j['durationMs'] != null
          ? Duration(milliseconds: j['durationMs'] as int)
          : null,
      source: SourceType.yandex,
      extra: albumId != null ? {'albumId': '$albumId'} : const {},
    );
  }

  /// Треклист альбома по его id (для страницы альбома). Ответ Яндекса — том(а)
  /// (`volumes`) со списками треков; парсер собирает их плоско.
  Future<List<Track>> albumTracks(String albumId, {int limit = 200}) async {
    _requireToken();
    try {
      final r = await _dio.get('$_base/albums/$albumId/with-tracks',
          options: _opts);
      return albumTracksFromResult(r.data['result']).take(limit).toList();
    } catch (e) {
      Diagnostics.instance.warn('ya.album', '$albumId: $e');
      return const [];
    }
  }

  @visibleForTesting
  static List<Track> albumTracksFromResult(dynamic result) {
    final volumes = (result?['volumes'] as List? ?? const []);
    final out = <Track>[];
    for (final vol in volumes) {
      if (vol is! List) continue;
      for (final t in vol) {
        if (t is Map) out.add(toTrack(t.cast<String, dynamic>()));
      }
    }
    return out;
  }

  void _requireToken() {
    if (_token == null || _token!.isEmpty) {
      throw SourceException(type, 'не задан токен (укажите в Настройках)');
    }
  }
}
