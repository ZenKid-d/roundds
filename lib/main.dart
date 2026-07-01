import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/downloads_controller.dart';
import 'core/providers.dart';
import 'data/aggregator.dart';
import 'data/recommendation_service.dart';
import 'data/sources/soundcloud_source.dart';
import 'data/sources/yandex_source.dart';
import 'data/sources/youtube_music_source.dart';
import 'domain/models/source_type.dart';
import 'playback/audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  // Общие экземпляры — их же отдаём в Riverpod через overrides,
  // чтобы UI и аудио-хендлер работали с одними источниками.
  final dio = buildAppDio();
  final youtube = YoutubeMusicSource(dio);
  final soundcloud =
      SoundcloudSource(dio, cachedClientId: prefs.getString('sc_client_id'));
  final yandex = YandexSource(dio);
  final aggregator = Aggregator({
    SourceType.youtube: youtube,
    SourceType.soundcloud: soundcloud,
    SourceType.yandex: yandex,
  });

  final downloads = DownloadsController(prefs, dio, aggregator);
  final reco = RecommendationService(soundcloud, yandex, aggregator);

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
  // Радио: докрутка очереди похожими треками.
  handler.radioExtender = reco.similarTo;
  // Кроссфейд — из сохранённой настройки.
  if (prefs.getBool('crossfade') ?? false) handler.setCrossfade(true);

  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        dioProvider.overrideWithValue(dio),
        youtubeSourceProvider.overrideWithValue(youtube),
        soundcloudSourceProvider.overrideWithValue(soundcloud),
        yandexSourceProvider.overrideWithValue(yandex),
        aggregatorProvider.overrideWithValue(aggregator),
        audioHandlerProvider.overrideWithValue(handler),
        downloadsProvider.overrideWith((ref) => downloads),
        recommendationServiceProvider.overrideWithValue(reco),
      ],
      child: const RoundedsApp(),
    ),
  );
}
