import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/downloads_controller.dart';
import 'core/net/doh_http.dart';
import 'core/net/doh_resolver.dart';
import 'core/providers.dart';
import 'core/update_service.dart';
import 'data/aggregator.dart';
import 'data/recommendation_service.dart';
import 'data/recs/recs_db.dart';
import 'data/recs/recs_store.dart';
import 'data/sources/soundcloud_source.dart';
import 'data/sources/vk_source.dart';
import 'data/sources/yandex_source.dart';
import 'data/sources/youtube_music_source.dart';
import 'domain/models/source_type.dart';
import 'domain/models/track.dart';
import 'playback/audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  // Обход блокировок DNS (DoH): если включён — все источники резолвят хосты
  // через DNS-over-HTTPS. Читаем до создания dio/YouTube (клиенты строятся
  // один раз на старте, поэтому смена настройки требует перезапуска).
  final doh = (prefs.getBool('doh_enabled') ?? false) ? DohResolver() : null;
  // HTTP-прокси (host:port) — обход блокировки по SNI/DPI (SoundCloud/YouTube),
  // которую DoH не пробивает. Читаем на старте (клиенты строятся один раз).
  final proxy = prefs.getString('http_proxy');

  // Общие экземпляры — их же отдаём в Riverpod через overrides,
  // чтобы UI и аудио-хендлер работали с одними источниками.
  final dio = buildAppDio(doh: doh, proxy: proxy);
  // Чистим оставшиеся после обновления APK из кэша.
  unawaited(UpdateService(dio).cleanupApks());
  final youtube =
      YoutubeMusicSource(dio, yt: buildYoutubeExplode(doh, proxy: proxy));
  youtube.streamQuality = prefs.getInt('stream_quality') ??
      ((prefs.getBool('data_saver') ?? false) ? 0 : 2);
  final soundcloud =
      SoundcloudSource(dio, cachedClientId: prefs.getString('sc_client_id'));
  final yandex = YandexSource(dio);
  final vk = VkSource(dio);
  final aggregator = Aggregator({
    SourceType.youtube: youtube,
    SourceType.soundcloud: soundcloud,
    SourceType.yandex: yandex,
    SourceType.vk: vk,
  });

  final downloads = DownloadsController(prefs, dio, aggregator);
  final reco = RecommendationService(youtube, soundcloud, yandex, aggregator);

  // Recs v2: event log / дизлайки (SQLite). Открываем БД, загружаем дизлайки,
  // один раз импортируем существующие сигналы (лайки/статы) из prefs.
  final recsStore = RecsStore(await RecsDb.open());
  await recsStore.init();
  if (!(prefs.getBool('recs_imported') ?? false)) {
    await recsStore.importFromLibrary(
      liked: _tracksFromPrefs(prefs.getString('liked')),
      topTracks: _statsFromPrefs(prefs.getString('stats')),
    );
    await prefs.setBool('recs_imported', true);
  }

  // Фоновое воспроизведение + уведомление + управление с локскрина.
  final handler = await AudioService.init(
    builder: () => RoundsAudioHandler(aggregator),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.roundds.audio',
      androidNotificationChannelName: 'Roundds',
      androidNotificationOngoing: true,
    ),
  );
  // Оффлайн: плеер сначала ищет скачанный файл.
  handler.localFileResolver = downloads.localPathFor;
  // Recs v2: докрутку очереди («радио»/волна) ставит движок волны в
  // playbackProvider (handler.radioExtender = waveEngine.extend) — заменяет
  // старую reco.similarTo-докрутку.
  // Кроссфейд + длительность + пропуск тишины — из сохранённых настроек.
  final cfSeconds = prefs.getDouble('crossfade_seconds');
  if (cfSeconds != null) handler.setCrossfadeSeconds(cfSeconds);
  if (prefs.getBool('crossfade') ?? false) handler.setCrossfade(true);
  if (prefs.getBool('skip_silence') ?? false) {
    unawaited(handler.setSkipSilence(true));
  }
  if (prefs.getBool('normalize') ?? false) {
    unawaited(handler.setNormalize(true));
  }
  if (prefs.getBool('gapless') ?? false) {
    unawaited(handler.setGapless(true));
  }

  // «Продолжить с места»: восстанавливаем прошлую сессию (на паузе).
  handler.bindSession(prefs);
  final rawSession = prefs.getString('last_session');
  if (rawSession != null) {
    try {
      final m = jsonDecode(rawSession) as Map<String, dynamic>;
      final tracks = (m['tracks'] as List)
          .map((e) => Track.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (tracks.isNotEmpty) {
        final posMs =
            prefs.getInt('last_position_ms') ?? (m['positionMs'] as int? ?? 0);
        unawaited(handler.restoreSession(
          tracks,
          m['index'] as int? ?? 0,
          Duration(milliseconds: posMs),
        ));
      }
    } catch (_) {/* повреждённая сессия — игнорируем */}
  }

  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        dioProvider.overrideWithValue(dio),
        youtubeSourceProvider.overrideWithValue(youtube),
        soundcloudSourceProvider.overrideWithValue(soundcloud),
        yandexSourceProvider.overrideWithValue(yandex),
        vkSourceProvider.overrideWithValue(vk),
        aggregatorProvider.overrideWithValue(aggregator),
        audioHandlerProvider.overrideWithValue(handler),
        downloadsProvider.overrideWith((ref) => downloads),
        recommendationServiceProvider.overrideWithValue(reco),
        recsStoreProvider.overrideWith((ref) => recsStore),
      ],
      child: const RoundedsApp(),
    ),
  );
}

/// Парсит список треков из prefs-ключа 'liked' (для одноразового импорта recs).
List<Track> _tracksFromPrefs(String? raw) {
  if (raw == null) return const [];
  try {
    return (jsonDecode(raw) as List)
        .map((e) => Track.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Парсит статы из prefs-ключа 'stats' — список {track, count}.
List<MapEntry<Track, int>> _statsFromPrefs(String? raw) {
  if (raw == null) return const [];
  try {
    return (jsonDecode(raw) as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      final t = Track.fromJson((m['track'] as Map).cast<String, dynamic>());
      return MapEntry(t, (m['count'] as num?)?.toInt() ?? 0);
    }).toList();
  } catch (_) {
    return const [];
  }
}
