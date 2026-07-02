import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Локальные уведомления (о завершении скачивания).
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  Future<void> _ensureInit() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _inited = true;
  }

  Future<void> show(String title, String body, {int id = 0}) async {
    try {
      await _ensureInit();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'com.roundds.downloads',
          'Загрузки',
          channelDescription: 'Уведомления о скачивании',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
      await _plugin.show(id, title, body, details);
    } catch (_) {/* без уведомления не критично */}
  }

  /// Постоянное уведомление с полосой прогресса (для скачивания плейлиста).
  /// [onlyAlertOnce] — не пикать на каждое обновление.
  Future<void> showProgress(
    String title,
    String body, {
    required int progress,
    required int max,
    int id = 1,
  }) async {
    try {
      await _ensureInit();
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'com.roundds.downloads',
          'Загрузки',
          channelDescription: 'Уведомления о скачивании',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          maxProgress: max,
          progress: progress.clamp(0, max),
        ),
      );
      await _plugin.show(id, title, body, details);
    } catch (_) {}
  }

  Future<void> cancel(int id) async {
    try {
      await _ensureInit();
      await _plugin.cancel(id);
    } catch (_) {}
  }
}
