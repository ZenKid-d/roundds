import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// riverpod 3 вынес ChangeNotifierProvider/StateProvider в legacy-модуль
// (курс на Notifier/AsyncNotifier) — полная миграция на новый API отдельной
// задачей (крупная перезапись всех провайдеров), пока используем legacy shim.
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/aggregator.dart';
import '../data/sources/soundcloud_source.dart';
import '../data/sources/vk_source.dart';
import '../data/sources/yandex_source.dart';
import '../data/sources/youtube_music_source.dart';
import '../domain/models/source_type.dart';
import 'diagnostics.dart';
import 'net/doh_http.dart';
import 'net/doh_resolver.dart';
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

const _maxRetries = 3;
const _retryBackoff = <Duration>[
  Duration(milliseconds: 300),
  Duration(milliseconds: 800),
  Duration(milliseconds: 1500),
];

/// Транзиентные сетевые сбои, которые есть смысл повторить: обрыв/сброс
/// соединения и таймауты (частый симптом DPI-сброса у SoundCloud/YouTube).
/// HTTP-статусы (400/403/…) сюда НЕ попадают — их повторять бессмысленно.
bool _isTransient(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
      return true;
    default:
      final msg = '${e.message ?? ''} ${e.error ?? ''}';
      return msg.contains('Connection closed') ||
          msg.contains('Connection reset') ||
          msg.contains('SocketException');
  }
}

/// Обход блокировок сети: [doh] != null включает DoH (резолв через
/// DNS-over-HTTPS + коннект по IP), [proxy] (`host:port`) — HTTP-прокси, который
/// сам резолвит и коннектит (обходит и DNS-, и SNI-блок; приоритетнее DoH).
/// Оба null/пусто — обычный системный DNS.
Dio buildAppDio({DohResolver? doh, String? proxy}) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: const {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Roundds/0.1',
    },
  ));
  if (doh != null || (proxy ?? '').trim().isNotEmpty) {
    dio.httpClientAdapter = buildDohDioAdapter(doh, proxy: proxy);
  }

  // Автоповтор транзиентных обрывов. Только идемпотентные GET; статусные ошибки
  // не трогаем. dio.fetch снова проходит цепочку интерцепторов, поэтому счётчик
  // попыток живёт в extra. Работает и поверх DoH-адаптера.
  dio.interceptors.add(InterceptorsWrapper(
    onError: (e, handler) async {
      final opts = e.requestOptions;
      final attempt = (opts.extra['retry'] as int?) ?? 0;
      final isGet = opts.method.toUpperCase() == 'GET';
      if (isGet && attempt < _maxRetries && _isTransient(e)) {
        final next = attempt + 1;
        Diagnostics.instance.warn('net.retry',
            '${opts.uri.host} попытка $next: ${e.message ?? e.type.name}');
        await Future<void>.delayed(
            _retryBackoff[attempt.clamp(0, _retryBackoff.length - 1)]);
        try {
          opts.extra['retry'] = next;
          final r = await dio.fetch<dynamic>(opts);
          return handler.resolve(r);
        } on DioException catch (err) {
          return handler.next(err);
        }
      }
      return handler.next(e);
    },
  ));

  return dio;
}

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

final vkSourceProvider =
    Provider<VkSource>((ref) => VkSource(ref.read(dioProvider)));

/// Агрегатор создаётся ОДИН раз (плеер держит на него ссылку).
/// Список включённых источников меняется через SettingsController.setEnabled.
final aggregatorProvider = Provider<Aggregator>((ref) {
  return Aggregator({
    SourceType.youtube: ref.read(youtubeSourceProvider),
    SourceType.soundcloud: ref.read(soundcloudSourceProvider),
    SourceType.yandex: ref.read(yandexSourceProvider),
    SourceType.vk: ref.read(vkSourceProvider),
  });
});

final settingsProvider =
    ChangeNotifierProvider<SettingsController>((ref) {
  final c = SettingsController(
    prefs: ref.read(prefsProvider),
    secure: ref.read(secureStorageProvider),
    yandex: ref.read(yandexSourceProvider),
    soundcloud: ref.read(soundcloudSourceProvider),
    vk: ref.read(vkSourceProvider),
    aggregator: ref.read(aggregatorProvider),
  );
  c.load();
  return c;
});

/// Переопределяется в main() экземпляром из AudioService.init().
final audioHandlerProvider = Provider<RoundsAudioHandler>(
    (ref) => throw UnimplementedError('audioHandler override missing'));

final lastfmServiceProvider = Provider<LastfmService>(
    (ref) => LastfmService(ref.read(dioProvider), ref.read(secureStorageProvider)));

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
  handler.radioExtender = engine.extend; // волна докручивает очередь (было reco)
  pc.onTrackStartedSignal = recs.recordStart;
  pc.onTrackEnded = (track, playedMs, durMs) {
    recs.recordPlayback(track, playedMs, durMs);
    // Скип меняет направление сессии и хвост очереди — только пока играет волна.
    if (engine.noteEnded(track, playedMs, durMs) && pc.isRadio) {
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
    if (ref.read(prefsProvider).getBool('autodl_likes') ?? false) {
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

/// Готовность каждого источника (для статусов в Drawer/Settings).
final sourceReadyProvider =
    FutureProvider.family<bool, SourceType>((ref, type) async {
  // пересчитываем при смене настроек (токен/включённость)
  ref.watch(settingsProvider);
  return ref.read(aggregatorProvider).isReady(type);
});
