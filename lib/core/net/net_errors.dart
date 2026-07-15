import 'dart:io';

/// Утилиты распознавания сетевых ошибок «хост не резолвится» — типичная картина
/// при блокировке/троттлинге у провайдера или неверном DNS у VPN:
/// `SocketException: Failed host lookup: '<host>' (OS Error: ..., errno = 7)`.
///
/// Такая ошибка приходит завёрнутой по-разному: `DioException` (dio) оборачивает
/// её в `.error`, а `youtube_explode_dart` (через package:http) — в
/// `ClientException`. Чтобы не тащить зависимости обоих пакетов, сводим проверку
/// к тексту сообщения (в нём всегда есть `Failed host lookup`), а для «сырого»
/// [SocketException] дополнительно смотрим `errno == 7`.

/// true, если ошибка — недоступность DNS (хост не получил IP).
bool isDnsBlockError(Object error) {
  if (error is SocketException && error.osError?.errorCode == 7) return true;
  return error.toString().contains('Failed host lookup');
}

/// Имя недоступного хоста из сообщения об ошибке (для диагностики), напр.
/// `Failed host lookup: 'api-v2.soundcloud.com'` → `api-v2.soundcloud.com`.
/// null — если в тексте хоста нет.
String? blockedHostOf(Object error) {
  final m =
      RegExp("Failed host lookup: '([^']+)'").firstMatch(error.toString());
  return m?.group(1);
}
