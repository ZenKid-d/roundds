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

  // Музыкальный трек по длительности: ~45 сек … 12 мин.
  static const _minSec = 45;
  static const _maxSec = 720;

  @override
  SourceType get type => SourceType.youtube;

  @override
  Future<bool> get isReady async => true;

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    try {
      final results = await _yt.search.search(query);
      return _onlyMusic(results).take(limit).toList();
    } catch (e) {
      throw SourceException(type, 'не удалось выполнить поиск ($e)');
    }
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
      // Набор клиентов, дающий играбельные ссылки: один из них почти всегда
      // отдаёт поток без троттлинга. Меньше клиентов = быстрее, но рвётся
      // воспроизведение (403/Source error), поэтому берём проверенную тройку.
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
      return PlayableStream(
        uri: audio.url,
        expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      );
    } catch (e) {
      throw SourceException(type, 'поток недоступен ($e)');
    }
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
      artworkUrl: v.thumbnails.highResUrl,
      duration: v.duration,
      source: SourceType.youtube,
    );
  }

  void dispose() => _yt.close();
}
