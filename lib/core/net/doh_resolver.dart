import 'dart:convert';

import 'package:dio/dio.dart';

/// DNS-over-HTTPS резолвер: получает IP хоста через DoH-эндпоинт, к которому
/// обращается ПО IP (1.1.1.1 / 8.8.8.8). Поэтому работает даже когда системный
/// DNS заблокирован (`Failed host lookup … errno = 7`) — literal-IP не требует
/// резолва, а TLS-сертификаты Cloudflare/Google включают эти IP в SAN.
class DohResolver {
  DohResolver({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  final Map<String, ({DateTime at, List<String> ips})> _cache = {};
  static const _ttl = Duration(minutes: 5);

  // Cloudflare (dns-json) и Google (совместимый формат) — оба по literal-IP.
  static const _endpoints = [
    'https://1.1.1.1/dns-query',
    'https://8.8.8.8/resolve',
  ];

  /// Первый A-record для [host]; null — если ни один эндпоинт не ответил.
  Future<String?> resolve(String host) async {
    if (_isIp(host)) return host; // уже IP — резолвить нечего
    final hit = _cache[host];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) {
      return hit.ips.isEmpty ? null : hit.ips.first;
    }
    for (final ep in _endpoints) {
      try {
        final ips = await _query(ep, host);
        if (ips.isNotEmpty) {
          _cache[host] = (at: DateTime.now(), ips: ips);
          return ips.first;
        }
      } catch (_) {/* пробуем следующий эндпоинт */}
    }
    return null;
  }

  Future<List<String>> _query(String endpoint, String host) async {
    final r = await _dio.get<dynamic>(
      endpoint,
      queryParameters: {'name': host, 'type': 'A'},
      options: Options(
        responseType: ResponseType.plain,
        headers: {'accept': 'application/dns-json'},
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
    final body = r.data;
    final data = body is String ? jsonDecode(body) : body;
    return parseAnswers(data);
  }

  /// Извлекает A-record IP из ответа DoH (`{"Answer":[{"type":1,"data":"1.2.3.4"}]}`).
  static List<String> parseAnswers(dynamic data) {
    if (data is! Map) return const [];
    final answers = (data['Answer'] as List? ?? const []);
    return answers
        .whereType<Map>()
        .where((a) => a['type'] == 1) // 1 = A-record
        .map((a) => a['data'])
        .whereType<String>()
        .where(_isIp)
        .toList();
  }

  static bool _isIp(String s) => RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(s);
}
