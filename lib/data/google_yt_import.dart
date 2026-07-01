import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/youtube/v3.dart';

import '../domain/models/source_type.dart';
import '../domain/models/track.dart';

/// Импорт лайков из YouTube Music через официальный YouTube Data API (OAuth).
/// Читает список «Мне понравилось» пользователя (videos.list?myRating=like).
class GoogleYtImportService {
  final GoogleSignIn _signIn =
      GoogleSignIn(scopes: const [YouTubeApi.youtubeReadonlyScope]);

  Future<GoogleSignInAccount?> get currentUser async =>
      _signIn.currentUser ?? await _signIn.signInSilently();

  /// Вход + чтение лайкнутых видео.
  Future<List<Track>> importLikedVideos({int max = 500}) async {
    final account = await _signIn.signIn();
    if (account == null) {
      throw Exception('Вход отменён');
    }
    final client = await _signIn.authenticatedClient();
    if (client == null) {
      throw Exception('Не удалось получить доступ к аккаунту');
    }
    try {
      final yt = YouTubeApi(client);
      final out = <Track>[];
      String? pageToken;
      do {
        final resp = await yt.videos.list(
          ['snippet', 'contentDetails'],
          myRating: 'like',
          maxResults: 50,
          pageToken: pageToken,
        );
        for (final v in resp.items ?? const <Video>[]) {
          final sn = v.snippet;
          final id = v.id;
          if (sn == null || id == null) continue;
          // Только музыка: категория YouTube «Music» = 10 (отсекает влоги,
          // смешные видео и прочее не-музыкальное из лайков).
          if (sn.categoryId != '10') continue;
          var artist = sn.channelTitle ?? 'YouTube';
          const topic = ' - Topic';
          if (artist.endsWith(topic)) {
            artist = artist.substring(0, artist.length - topic.length);
          }
          out.add(Track(
            id: id,
            title: sn.title ?? '',
            artist: artist,
            artworkUrl: sn.thumbnails?.high?.url ??
                sn.thumbnails?.medium?.url ??
                sn.thumbnails?.default_?.url,
            duration: _parseIso(v.contentDetails?.duration),
            source: SourceType.youtube,
          ));
          if (out.length >= max) break;
        }
        pageToken = resp.nextPageToken;
      } while (pageToken != null && out.length < max);
      return out;
    } finally {
      client.close();
    }
  }

  Future<void> signOut() => _signIn.signOut();
}

/// Разбор ISO-8601 длительности (PT#H#M#S).
Duration? _parseIso(String? iso) {
  if (iso == null) return null;
  final m = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?').firstMatch(iso);
  if (m == null) return null;
  final h = int.tryParse(m.group(1) ?? '0') ?? 0;
  final min = int.tryParse(m.group(2) ?? '0') ?? 0;
  final s = int.tryParse(m.group(3) ?? '0') ?? 0;
  final d = Duration(hours: h, minutes: min, seconds: s);
  return d == Duration.zero ? null : d;
}
