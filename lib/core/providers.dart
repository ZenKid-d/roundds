import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/aggregator.dart';
import '../data/sources/soundcloud_source.dart';
import '../data/sources/yandex_source.dart';
import '../data/sources/youtube_music_source.dart';
import '../domain/models/source_type.dart';
import '../playback/playback_controller.dart';
import 'library_controller.dart';
import 'settings_controller.dart';

/// Переопределяется в main() реальным экземпляром.
final prefsProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('prefs override missing'));

final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: const {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Roundds/0.1',
    },
  ));
  return dio;
});

final youtubeSourceProvider =
    Provider<YoutubeMusicSource>((ref) => YoutubeMusicSource());

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
    aggregator: ref.read(aggregatorProvider),
  );
  c.load();
  return c;
});

final playbackProvider = ChangeNotifierProvider<PlaybackController>(
    (ref) => PlaybackController(ref.read(aggregatorProvider)));

final libraryProvider = ChangeNotifierProvider<LibraryController>(
    (ref) => LibraryController(ref.read(prefsProvider)));

/// Готовность каждого источника (для статусов в Drawer/Settings).
final sourceReadyProvider =
    FutureProvider.family<bool, SourceType>((ref, type) async {
  // пересчитываем при смене настроек (токен/включённость)
  ref.watch(settingsProvider);
  return ref.read(aggregatorProvider).isReady(type);
});
