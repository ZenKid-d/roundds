import 'dart:io';

import 'package:dio/io.dart';
import 'package:http/io_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'doh_resolver.dart';

/// `HttpClient` (dart:io), который подключается к IP от [doh], но TLS/SNI и
/// проверку сертификата оставляет на исходное имя хоста (это делает сам
/// `HttpClient` — фабрика возвращает обычный `Socket`, поэтому SNI берётся из
/// `uri.host`). Если DoH не дал IP — коннектимся по имени (системный DNS), т.е.
/// не хуже обычного поведения.
HttpClient buildDohHttpClient(DohResolver doh) {
  final client = HttpClient();
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    final ip = await doh.resolve(uri.host);
    return Socket.startConnect(ip ?? uri.host, uri.port);
  };
  return client;
}

/// Адаптер dio, резолвящий хосты через DoH.
IOHttpClientAdapter buildDohDioAdapter(DohResolver doh) =>
    IOHttpClientAdapter(createHttpClient: () => buildDohHttpClient(doh));

/// `YoutubeExplode`, чей внутренний http-клиент (package:http) ходит через DoH.
/// Именно он резолвит поток YouTube (`/youtubei/v1/player`) — без DoH это
/// падает на системном DNS (ошибки `yt.resolve` в диагностике). null → обычный.
YoutubeExplode buildYoutubeExplode(DohResolver? doh) {
  if (doh == null) return YoutubeExplode();
  return YoutubeExplode(YoutubeHttpClient(IOClient(buildDohHttpClient(doh))));
}
