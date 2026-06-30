import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Фон + уведомление с контролами для нашего плеера.
  // Не валим запуск приложения, если инициализация не удалась —
  // деградируем до плеера без фонового уведомления.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.roundds.audio',
      androidNotificationChannelName: 'Roundds',
      androidNotificationOngoing: true,
    );
  } catch (e, st) {
    debugPrint('JustAudioBackground.init failed: $e\n$st');
  }

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
      ],
      child: const RoundedsApp(),
    ),
  );
}
