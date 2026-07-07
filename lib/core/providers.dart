import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/aggregator.dart';
import '../data/sources/soundcloud_source.dart';
import '../data/sources/yandex_source.dart';
import '../data/sources/youtube_music_source.dart';
import '../domain/models/source_type.dart';
import '../domain/models/track.dart';
import 'diagnostics.dart';
import 'premium/premium_controller.dart';
import 'premium/wave_quota.dart';
import '../data/google_yt_import.dart';
import '../data/lastfm_service.dart';
import '../data/lyrics_service.dart';
import '../data/recommendation_service.dart';
import '../data/recs/recs_providers.dart';
import '../data/recs/recs_store.dart';
import '../data/spotify_import.dart';
import '../data/translation_service.dart';
import 'theme/theme_settings.dart';
import '../playback/audio_handler.dart';
import '../playback/playback_controller.dart';
import 'downloads_controller.dart';
import 'library_controller.dart';
import 'settings_controller.dart';
import 'sleep_timer.dart';
import 'update_controller.dart';
import 'update_service.dart';

/// Переопределяется в main() реальным экземпляром.
final prefsProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('prefs override missing'));

final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

/// Внутренний журнал диагностики (кольцевой буфер) — тот же синглтон, в который
/// пишут источники. Обычный Provider (не ChangeNotifierProvider): синглтон живёт
/// вне жизненного цикла провайдера, иначе Riverpod вызвал бы на нём dispose при
/// уничтожении ProviderScope. Экран подписывается на изменения через
/// ListenableBuilder.
final diagnosticsProvider =
    Provider<Diagnostics>((ref) => Diagnostics.instance);

Dio buildAppDio() => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Roundds/0.1',
      },
    ));

final dioProvider = Provider<Dio>((ref) => buildAppDio());

final youtubeSourceProvider = Provider<YoutubeMusicSource>(
    (ref) => YoutubeMusicSource(ref.read(dioProvider)));

final soundcloudSourceProvider = Provider<SoundcloudSource>((ref) {
  final prefs = ref.read(prefsProvider);
  return SoundcloudSource(ref.read(dioProvider),
      cachedClientId: prefs.getString('sc_client_id'));
});

final yandexSourceProvider =
    Provider<YandexSource>((ref) => YandexSource(ref.read(dioProvider)));

/// Агрегатор создаётся ОДИН раз (плеер держит на него ссылку).
/// Список включённых источников меняется через SettingsController.setEnabled.
final aggregatorProvider = Provider<Aggregator>((ref) {
  return Aggregator({
    SourceType.youtube: ref.read(youtubeSourceProvider),
    SourceType.soundcloud: ref.read(soundcloudSourceProvider),
    SourceType.yandex: ref.read(yandexSourceProvider),
  });
});

final settingsProvider =
    ChangeNotifierProvider<SettingsController>((ref) {
  final c = SettingsController(
    prefs: ref.read(prefsProvider),
    secure: ref.read(secureStorageProvider),
    yandex: ref.read(yandexSourceProvider),
    soundcloud: ref.read(soundcloudSourceProvider),
    aggregator: ref.read(aggregatorProvider),
  );
  c.load();
  return c;
});

/// Переопределяется в main() экземпляром из AudioService.init().
final audioHandlerProvider = Provider<RoundsAudioHandler>(
    (ref) => throw UnimplementedError('audioHandler override missing'));

final lastfmServiceProvider = Provider<LastfmService>(
    (ref) => LastfmService(ref.read(dioProvider), ref.read(prefsProvider)));

final spotifyImportProvider = Provider<SpotifyImportService>(
    (ref) => SpotifyImportService(ref.read(dioProvider)));

/// Переопределяется в main() после асинхронного открытия БД recs.
final recsStoreProvider = ChangeNotifierProvider<RecsStore>(
    (ref) => throw UnimplementedError('recsStore override missing'));

final ChangeNotifierProvider<PlaybackController> playbackProvider =
    ChangeNotifierProvider<PlaybackController>((ref) {
  final pc = PlaybackController(ref.read(audioHandlerProvider));
  pc.onListened = (ms) => ref.read(libraryProvider).addListened(ms);
  final lastfm = ref.read(lastfmServiceProvider);
  pc.onNowPlaying = lastfm.updateNowPlaying;
  pc.onScrobble = lastfm.scrobble;
  // Recs v2: event log из плеера + движок волны (докрутка + real-time петля).
  final recs = ref.read(recsStoreProvider);
  final engine = ref.read(waveEngineProvider);
  final handler = ref.read(audioHandlerProvider);
  final premium = ref.read(premiumProvider);
  final quota = ref.read(waveQuotaProvider);
  // Бесплатным волна докручивается только пока не исчерпан дневной лимит.
  bool waveAllowed() => premium.isPremium || quota.freeHasQuota;
  handler.radioExtender = (seed) async {
    if (!waveAllowed()) return const <Track>[];
    return engine.extend(seed);
  };
  pc.onTrackStartedSignal = recs.recordStart;
  pc.onTrackEnded = (track, playedMs, durMs) {
    recs.recordPlayback(track, playedMs, durMs);
    // Трек волны, реально прослушанный (≥30с), тратит дневной лимит бесплатных.
    if (pc.isRadio && !premium.isPremium && playedMs >= 30000) {
      quota.noteWavePlay();
    }
    // Скип меняет направление сессии и хвост очереди — только пока играет волна.
    if (engine.noteEnded(track, playedMs, durMs) && pc.isRadio && waveAllowed()) {
      final cur = pc.current;
      if (cur != null) {
        engine.extend(cur).then((tail) {
          if (tail.isNotEmpty) handler.replaceUpcoming(tail);
        });
      }
    }
  };
  return pc;
});

/// Позиция воспроизведения отдельным стримом — чтобы прогресс тикал, не
/// перестраивая весь плеер.
final positionProvider = StreamProvider.autoDispose<Duration>(
    (ref) => ref.watch(audioHandlerProvider).player.positionStream);

final ChangeNotifierProvider<LibraryController> libraryProvider =
    ChangeNotifierProvider<LibraryController>((ref) {
  final c = LibraryController(ref.read(prefsProvider));
  // Авто-скачивание лайкнутого трека, если включено в настройках.
  c.onTrackLiked = (track) {
    ref.read(recsStoreProvider).recordLike(track); // recs v2: сигнал лайка
    ref.read(waveEngineProvider).noteLike(track); // волна: усилить направление
    // Авто-скачивание — Premium-функция.
    if ((ref.read(prefsProvider).getBool('autodl_likes') ?? false) &&
        ref.read(premiumProvider).isPremium) {
      ref.read(downloadsProvider).download(track);
    }
  };
  return c;
});

final lyricsServiceProvider =
    Provider<LyricsService>((ref) => LyricsService(ref.read(dioProvider)));

final updateServiceProvider =
    Provider<UpdateService>((ref) => UpdateService(ref.read(dioProvider)));

final translationServiceProvider =
    Provider<TranslationService>((ref) => TranslationService(ref.read(dioProvider)));

/// Реактивная настройка «реальный визуализатор» (prefs не реактивен сам по себе).
final realVisualizerProvider = StateProvider<bool>(
    (ref) => ref.read(prefsProvider).getBool('real_visualizer') ?? false);

final updateControllerProvider = ChangeNotifierProvider<UpdateController>(
    (ref) => UpdateController(ref.read(updateServiceProvider)));

final sleepTimerProvider = ChangeNotifierProvider<SleepTimerController>(
    (ref) => SleepTimerController());

final themeSettingsProvider = ChangeNotifierProvider<ThemeSettingsController>(
    (ref) => ThemeSettingsController(ref.read(prefsProvider)));

/// Переопределяется в main() (нужны те же экземпляры источников/агрегатора).
final recommendationServiceProvider = Provider<RecommendationService>(
    (ref) => throw UnimplementedError('reco override missing'));

final googleYtImportProvider =
    Provider<GoogleYtImportService>((ref) => GoogleYtImportService());

/// Переопределяется в main() экземпляром, связанным с плеером (оффлайн-файлы).
final downloadsProvider = ChangeNotifierProvider<DownloadsController>(
    (ref) => throw UnimplementedError('downloads override missing'));

/// Premium-статус (подписанные Boosty-коды). Переопределяется в main()
/// уже загруженным экземпляром — чтобы качество клампилось на старте.
final premiumProvider = ChangeNotifierProvider<PremiumController>(
    (ref) => throw UnimplementedError('premium override missing'));

/// Дневной лимит «Моей волны» для бесплатной версии.
final waveQuotaProvider =
    Provider<WaveQuota>((ref) => WaveQuota(ref.read(prefsProvider)));

/// Готовность каждого источника (для статусов в Drawer/Settings).
final sourceReadyProvider =
    FutureProvider.family<bool, SourceType>((ref, type) async {
  // пересчитываем при смене настроек (токен/включённость)
  ref.watch(settingsProvider);
  return ref.read(aggregatorProvider).isReady(type);
});
