import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Импорт публичного плейлиста/альбома Spotify по ссылке — тянем ТОЛЬКО
/// метаданные (название + артист) со страницы embed, играем потом из
/// свободных источников (YouTube/SoundCloud). Это не обход DRM: аудио Spotify
/// не трогаем, лишь названия треков для поиска в нашем агрегаторе.
class SpotifyImportService {
  SpotifyImportService(this._dio);
  final Dio _dio;

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  /// По ссылке Spotify возвращает название и список поисковых запросов
  /// «артист трек». Бросает [SpotifyImportException] с человекочитаемой
  /// причиной при неудаче.
  Future<({String name, List<String> queries})> fetch(String urlOrId) async {
    final id = extractId(urlOrId);
    if (id == null) {
      throw SpotifyImportException('Не похоже на ссылку Spotify.');
    }
    final type = extractType(urlOrId);
    late final String html;
    try {
      final r = await _dio.get<String>(
        'https://open.spotify.com/embed/$type/$id',
        options: Options(
            responseType: ResponseType.plain,
            headers: {'User-Agent': _ua}),
      );
      html = r.data ?? '';
    } catch (e) {
      throw SpotifyImportException('Не удалось открыть страницу Spotify ($e).');
    }
    return parseEmbed(html);
  }

  /// Разбирает HTML embed-страницы Spotify в (название, запросы). Вынесено
  /// отдельно и тестируемо — скрейпинг ломок, ловим смену формата тестом.
  @visibleForTesting
  static ({String name, List<String> queries}) parseEmbed(String html) {
    final m = RegExp(
      r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (m == null) {
      throw SpotifyImportException(
          'Не удалось прочитать плейлист (Spotify мог изменить формат).');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(m.group(1)!) as Map<String, dynamic>;
    } catch (_) {
      throw SpotifyImportException('Не удалось разобрать данные Spotify.');
    }
    final entity = _dig(data, const [
      'props',
      'pageProps',
      'state',
      'data',
      'entity',
    ]);
    if (entity is! Map) {
      throw SpotifyImportException(
          'Плейлист недоступен (закрытый или пустой?).');
    }
    final name =
        (entity['name'] ?? entity['title'] ?? 'Spotify').toString().trim();
    final trackList = (entity['trackList'] as List?) ?? const [];
    final queries = <String>[];
    for (final t in trackList) {
      if (t is! Map) continue;
      final title = (t['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final artist = (t['subtitle'] ?? '').toString().trim();
      queries.add(artist.isEmpty ? title : '$artist $title');
    }
    if (queries.isEmpty) {
      throw SpotifyImportException('В плейлисте не найдено треков.');
    }
    return (name: name.isEmpty ? 'Spotify' : name, queries: queries);
  }

  /// playlist или album (по умолчанию playlist).
  @visibleForTesting
  static String extractType(String url) =>
      (url.contains('/album/') || url.contains(':album:'))
          ? 'album'
          : 'playlist';

  /// ID Spotify — 22 символа base62. Поддерживаем ссылку, uri и «голый» id.
  @visibleForTesting
  static String? extractId(String input) {
    final byUrl =
        RegExp(r'(?:playlist|album)[:/]([A-Za-z0-9]{22})').firstMatch(input);
    if (byUrl != null) return byUrl.group(1);
    final bare = RegExp(r'^[A-Za-z0-9]{22}$').firstMatch(input.trim());
    return bare?.group(0);
  }

  static dynamic _dig(dynamic node, List<String> path) {
    for (final key in path) {
      if (node is Map && node.containsKey(key)) {
        node = node[key];
      } else {
        return null;
      }
    }
    return node;
  }
}

class SpotifyImportException implements Exception {
  SpotifyImportException(this.message);
  final String message;
  @override
  String toString() => message;
}
