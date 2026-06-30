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
  YoutubeMusicSource();

  final YoutubeExplode _yt = YoutubeExplode();

  @override
  SourceType get type => SourceType.youtube;

  @override
  Future<bool> get isReady async => true;

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    try {
      final results = await _yt.search.search(query);
      return results.take(limit).map(_videoToTrack).toList();
    } catch (e) {
      throw SourceException(type, 'не удалось выполнить поиск ($e)');
    }
  }

  @override
  Future<List<Track>> feed({int limit = 20}) async {
    // У youtube_explode нет прямого «чарта»; используем сид-запросы как ленту.
    const seeds = ['Top hits 2025', 'Trending music', 'New music this week'];
    final out = <Track>[];
    for (final s in seeds) {
      try {
        final r = await _yt.search.search(s);
        out.addAll(r.take((limit / seeds.length).ceil()).map(_videoToTrack));
      } catch (_) {/* пропускаем неудачный сид */}
      if (out.length >= limit) break;
    }
    return out.take(limit).toList();
  }

  @override
  Future<PlayableStream> resolveStream(Track track) async {
    try {
      // androidVr — самый устойчивый клиент (без троттлинга и po_token),
      // дальше откат на android/ios.
      final manifest = await _yt.videos.streamsClient.getManifest(
        track.id,
        ytClients: [
          YoutubeApiClient.androidVr,
          YoutubeApiClient.android,
          YoutubeApiClient.ios,
        ],
      );
      final audio = manifest.audioOnly.isNotEmpty
          ? manifest.audioOnly.withHighestBitrate()
          : manifest.muxed.withHighestBitrate();
      // URL действителен ограниченное время и привязан к сессии — короткий TTL.
      return PlayableStream(
        uri: audio.url,
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );
    } catch (e) {
      throw SourceException(type, 'поток недоступен ($e)');
    }
  }

  Track _videoToTrack(Video v) => Track(
        id: v.id.value,
        title: v.title,
        artist: v.author,
        artworkUrl: v.thumbnails.highResUrl,
        duration: v.duration,
        source: SourceType.youtube,
      );

  void dispose() => _yt.close();
}
