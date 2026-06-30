import 'package:dio/dio.dart';

/// Текст песни: обычный и/или синхронизированный (LRC).
class Lyrics {
  final String? plain;
  final String? synced;
  const Lyrics({this.plain, this.synced});

  bool get isEmpty =>
      (plain == null || plain!.isEmpty) && (synced == null || synced!.isEmpty);
  bool get hasSynced => synced != null && synced!.isNotEmpty;
}

/// Текст песен через бесплатный публичный lrclib.net (без ключа).
class LyricsService {
  LyricsService(this._dio);
  final Dio _dio;

  static const _base = 'https://lrclib.net/api';

  Future<Lyrics?> fetch({
    required String artist,
    required String title,
    Duration? duration,
  }) async {
    // Точный матч по артисту/названию/длительности.
    try {
      final r = await _dio.get('$_base/get', queryParameters: {
        'artist_name': artist,
        'track_name': title,
        if (duration != null) 'duration': duration.inSeconds,
      });
      final d = r.data as Map;
      final lyr = Lyrics(
        plain: d['plainLyrics'] as String?,
        synced: d['syncedLyrics'] as String?,
      );
      if (!lyr.isEmpty) return lyr;
    } catch (_) {/* пробуем поиск */}

    // Фолбэк — поиск.
    try {
      final r = await _dio.get('$_base/search', queryParameters: {
        'track_name': title,
        'artist_name': artist,
      });
      final list = (r.data as List?) ?? [];
      if (list.isNotEmpty) {
        final d = list.first as Map;
        return Lyrics(
          plain: d['plainLyrics'] as String?,
          synced: d['syncedLyrics'] as String?,
        );
      }
    } catch (_) {/* нет текста */}
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
