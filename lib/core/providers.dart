import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/aggregator.dart';
import '../data/sources/soundcloud_source.dart';
import '../data/sources/yandex_source.dart';
import '../data/sources/youtube_music_source.dart';
import '../domain/models/source_type.dart';
import '../data/google_yt_import.dart';
import '../data/lyrics_service.dart';
import '../data/recommendation_service.dart';
import 'theme/theme_settings.dart';
import '../playback/audio_handler.dart';
import '../playback/playback_controller.dart';
import 'downloads_controller.dart';
import 'library_controller.dart';
import 'settings_controller.dart';
import 'sleep_timer.dart';

/// Переопределяется в main() реальным экземпляром.
final prefsProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('prefs override missing'));

final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

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

final playbackProvider = ChangeNotifierProvider<PlaybackController>((ref) {
  final pc = PlaybackController(ref.read(audioHandlerProvider));
  pc.onListened = (ms) => ref.read(libraryProvider).addListened(ms);
  return pc;
});

/// Позиция воспроизведения отдельным стримом — чтобы прогресс тикал, не
/// перестраивая весь плеер.
final positionProvider = StreamProvider.autoDispose<Duration>(
    (ref) => ref.watch(audioHandlerProvider).player.positionStream);

final libraryProvider = ChangeNotifierProvider<LibraryController>(
    (ref) => LibraryController(ref.read(prefsProvider)));

final lyricsServiceProvider =
    Provider<LyricsService>((ref) => LyricsService(ref.read(dioProvider)));

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
