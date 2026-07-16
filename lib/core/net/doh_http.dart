import 'dart:io';

import 'package:dio/io.dart';
import 'package:http/io_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'doh_resolver.dart';

/// `HttpClient` (dart:io) с обходом блокировок.
///
/// • [proxy] (`host:port`) — если задан, весь трафик идёт через HTTP-прокси:
///   прокси сам резолвит хост и устанавливает соединение, поэтому обходятся и
///   DNS-, и SNI-блокировка (локальный провайдер видит только адрес прокси).
///   Прокси имеет приоритет над DoH (их механизмы соединения несовместимы:
///   `connectionFactory` перекрыл бы прокси).
/// • [doh] — иначе подключаемся к IP от DoH, а TLS/SNI и проверку сертификата
///   оставляем на исходное имя хоста (фабрика возвращает обычный `Socket`,
///   поэтому SNI берётся из `uri.host`). Если DoH не дал IP — по имени
///   (системный DNS), т.е. не хуже обычного поведения.
/// • ни то ни другое — обычный `HttpClient`.
HttpClient buildDohHttpClient(DohResolver? doh, {String? proxy}) {
  final client = HttpClient();
  final p = (proxy ?? '').trim();
  if (p.isNotEmpty) {
    client.findProxy = (_) => 'PROXY $p';
  } else if (doh != null) {
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final ip = await doh.resolve(uri.host);
      return Socket.startConnect(ip ?? uri.host, uri.port);
    };
  }
  return client;
}

/// Адаптер dio с обходом (DoH и/или прокси) — см. [buildDohHttpClient].
IOHttpClientAdapter buildDohDioAdapter(DohResolver? doh, {String? proxy}) =>
    IOHttpClientAdapter(
        createHttpClient: () => buildDohHttpClient(doh, proxy: proxy));

/// `YoutubeExplode`, чей внутренний http-клиент (package:http) ходит через DoH
/// и/или прокси. Именно он резолвит поток YouTube (`/youtubei/v1/player`) — без
/// обхода это падает на системном DNS (ошибки `yt.resolve`). Если ни DoH, ни
/// прокси не заданы — обычный клиент.
YoutubeExplode buildYoutubeExplode(DohResolver? doh, {String? proxy}) {
  if (doh == null && (proxy ?? '').trim().isEmpty) return YoutubeExplode();
  return YoutubeExplode(
      YoutubeHttpClient(IOClient(buildDohHttpClient(doh, proxy: proxy))));
}
