import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

/// Текст песни: обычный и/или синхронизированный (LRC).
class Lyrics {
  final String? plain;
  final String? synced;
  const Lyrics({this.plain, this.synced});

  bool get isEmpty =>
      (plain == null || plain!.isEmpty) && (synced == null || synced!.isEmpty);
  bool get hasSynced => synced != null && synced!.isNotEmpty;
}

/// Текст песен из нескольких публичных источников (без ключей):
/// lrclib.net → NetEase (music.163.com) → lyrics.ovh.
/// Предпочтение — синхронному тексту (LRC) из любого источника.
class LyricsService {
  LyricsService(this._dio);
  final Dio _dio;

  Future<Lyrics?> fetch({
    required String artist,
    required String title,
    Duration? duration,
  }) async {
    final lrclib = await _lrclib(artist, title, duration);
    if (lrclib != null && lrclib.hasSynced) return lrclib;

    final netease = await _netease(artist, title);
    if (netease != null && netease.hasSynced) return netease;

    if (lrclib != null && !lrclib.isEmpty) return lrclib;
    if (netease != null && !netease.isEmpty) return netease;

    final ovh = await _lyricsOvh(artist, title);
    if (ovh != null && !ovh.isEmpty) return ovh;

    final genius = await _genius(artist, title);
    if (genius != null && !genius.isEmpty) return genius;

    return null;
  }

  // --- lrclib.net ---
  Future<Lyrics?> _lrclib(
      String artist, String title, Duration? duration) async {
    try {
      final r = await _dio.get('https://lrclib.net/api/get', queryParameters: {
        'artist_name': artist,
        'track_name': title,
        if (duration != null) 'duration': duration.inSeconds,
      });
      final d = r.data as Map;
      final lyr = Lyrics(
          plain: d['plainLyrics'] as String?,
          synced: d['syncedLyrics'] as String?);
      if (!lyr.isEmpty) return lyr;
    } catch (_) {/* пробуем поиск */}
    try {
      final r = await _dio.get('https://lrclib.net/api/search',
          queryParameters: {'track_name': title, 'artist_name': artist});
      final list = (r.data as List?) ?? [];
      if (list.isNotEmpty) {
        final d = list.first as Map;
        return Lyrics(
            plain: d['plainLyrics'] as String?,
            synced: d['syncedLyrics'] as String?);
      }
    } catch (_) {}
    return null;
  }

  // --- NetEase (music.163.com), часто есть синхронный LRC ---
  Future<Lyrics?> _netease(String artist, String title) async {
    final opts = Options(headers: const {
      'Referer': 'https://music.163.com/',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
    });
    try {
      final s = await _dio.get('https://music.163.com/api/search/get',
          queryParameters: {
            's': '$artist $title',
            'type': 1,
            'limit': 5,
          },
          options: opts);
      final songs = (s.data['result']?['songs'] as List?) ?? [];
      if (songs.isEmpty) return null;
      final id = (songs.first as Map)['id'];
      final l = await _dio.get('https://music.163.com/api/song/lyric',
          queryParameters: {'id': id, 'lv': 1, 'kv': 1, 'tv': -1},
          options: opts);
      final lrc = l.data['lrc']?['lyric'] as String?;
      if (lrc == null || lrc.isEmpty) return null;
      // Есть таймкоды → синхронный, иначе обычный.
      final synced = RegExp(r'\[\d{1,2}:\d{2}').hasMatch(lrc);
      return synced ? Lyrics(synced: lrc) : Lyrics(plain: lrc);
    } catch (_) {
      return null;
    }
  }

  // --- Genius (обычный текст; API не отдаёт текст, поэтому разбор страницы) ---
  Future<Lyrics?> _genius(String artist, String title) async {
    final opts = Options(headers: const {
      'Referer': 'https://genius.com/',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
    });
    try {
      final s = await _dio.get('https://genius.com/api/search/multi',
          queryParameters: {'q': '$artist $title'}, options: opts);
      final sections = (s.data['response']?['sections'] as List?) ?? [];
      String? url;
      for (final sec in sections) {
        if ((sec as Map)['type'] == 'song') {
          final hits = (sec['hits'] as List?) ?? [];
          if (hits.isNotEmpty) {
            url = (hits.first as Map)['result']?['url'] as String?;
            break;
          }
        }
      }
      if (url == null) return null;

      final page = await _dio.get<String>(url,
          options: Options(responseType: ResponseType.plain, headers: {
            'User-Agent': opts.headers!['User-Agent'],
          }));
      var body = page.data ?? '';
      // Переносы строк Genius держит в <br> — сохраняем их до разбора.
      body = body.replaceAll(RegExp(r'<br\s*/?>'), '\n');
      final doc = html_parser.parse(body);
      final containers =
          doc.querySelectorAll('[data-lyrics-container="true"]');
      final text = containers.map((e) => e.text).join('\n').trim();
      if (text.isEmpty) return null;
      return Lyrics(plain: text);
    } catch (_) {
      return null;
    }
  }

  // --- lyrics.ovh (обычный текст) ---
  Future<Lyrics?> _lyricsOvh(String artist, String title) async {
    try {
      final r = await _dio.get(
          'https://api.lyrics.ovh/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}');
      final plain = r.data['lyrics'] as String?;
      if (plain != null && plain.trim().isNotEmpty) {
        return Lyrics(plain: plain.trim());
      }
    } catch (_) {}
    return null;
  }
}

/// Разобранная строка синхронизированного текста.
class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

/// Парсит LRC ([mm:ss.xx] текст) в отсортированный список строк.
List<LyricLine> parseLrc(String lrc) {
  final out = <LyricLine>[];
  final re = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  for (final raw in lrc.split('\n')) {
    final matches = re.allMatches(raw).toList();
    if (matches.isEmpty) continue;
    final text = raw.replaceAll(re, '').trim();
    for (final m in matches) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final frac = m.group(3);
      final ms = frac == null
          ? 0
          : int.parse(frac.padRight(3, '0').substring(0, 3));
      out.add(LyricLine(
        Duration(minutes: min, seconds: sec, milliseconds: ms),
        text,
      ));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}
