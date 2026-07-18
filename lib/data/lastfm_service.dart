import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/track.dart';

/// Скробблинг в Last.fm. Пользователь создаёт API-аккаунт (key+secret) и входит
/// логином/паролем (auth.getMobileSession) — пароль не сохраняется, хранится
/// только session key.
///
/// Все секреты (apiKey, secret, sessionKey) лежат в flutter_secure_storage
/// (раньше — в SharedPreferences plaintext, что позволяло утечь через бэкап).
/// Загрузка из secure storage асинхронна, поэтому после конструктора нужно
/// вызвать [init] (это делает main.dart перед runApp). До init сервис считает
/// себя без creds — безопасно, ничего не скробблит.
class LastfmService {
  LastfmService(this._dio, this._storage) {
    // Одноразовая миграция старых plaintext-ключей из prefs в secure storage.
    // Бесполезна после первого успешного запуска, но безболезненна: если
    // в prefs ничего нет, просто нет-op.
    _migrateFromPrefs();
  }

  final Dio _dio;
  final FlutterSecureStorage _storage;
  static const _base = 'https://ws.audioscrobbler.com/2.0/';

  // Ключи в secure storage (Keystore/Keychain на устройстве).
  static const _kApiKey = 'lastfm_key';
  static const _kSecret = 'lastfm_secret';
  static const _kSessionKey = 'lastfm_sk';
  static const _kUsername = 'lastfm_user';
  // Флаг того, что миграция из prefs уже выполнена (чтобы не дёргать prefs
  // на каждом старке после перехода).
  static const _kMigrated = 'lastfm_migrated';

  String? _apiKey;
  String? _secret;
  String? _sessionKey;
  String? _username;
  bool _loaded = false;

  /// Загружает секреты из secure storage. Вызывается из main() перед runApp.
  /// Идемпотентен. После вызова сервис готов к скробблингу (если creds есть).
  Future<void> init() async {
    if (_loaded) return;
    _apiKey = await _storage.read(key: _kApiKey);
    _secret = await _storage.read(key: _kSecret);
    _sessionKey = await _storage.read(key: _kSessionKey);
    _username = await _storage.read(key: _kUsername);
    _loaded = true;
  }

  /// Миграция старых plaintext-значений из SharedPreferences в secure storage.
  /// Запускается один раз (флаг lastfm_migrated), затем ключи из prefs
  /// удаляются. Если prefs пусты или миграция уже была — нет-op.
  Future<void> _migrateFromPrefs() async {
    // Нельзя использовать secure_storage для флага _kMigrated (он сам по себе
    // признак, что secure storage уже задействован) — держим флаг в prefs.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kMigrated) ?? false) return;
    final k = prefs.getString('lastfm_key');
    final s = prefs.getString('lastfm_secret');
    final sk = prefs.getString('lastfm_sk');
    final u = prefs.getString('lastfm_user');
    if (k != null) await _storage.write(key: _kApiKey, value: k);
    if (s != null) await _storage.write(key: _kSecret, value: s);
    if (sk != null) await _storage.write(key: _kSessionKey, value: sk);
    if (u != null) await _storage.write(key: _kUsername, value: u);
    // Чистим plaintext из prefs — теперь они в secure storage.
    await prefs.remove('lastfm_key');
    await prefs.remove('lastfm_secret');
    await prefs.remove('lastfm_sk');
    await prefs.remove('lastfm_user');
    await prefs.setBool(_kMigrated, true);
  }

  bool get enabled => _sessionKey != null && _apiKey != null;
  bool get hasCredentials =>
      (_apiKey?.isNotEmpty ?? false) && (_secret?.isNotEmpty ?? false);
  String? get username => _username;

  Future<void> saveCredentials(String apiKey, String secret) async {
    _apiKey = apiKey.trim();
    _secret = secret.trim();
    await _storage.write(key: _kApiKey, value: _apiKey!);
    await _storage.write(key: _kSecret, value: _secret!);
    _loaded = true;
  }

  String _sign(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    final sb = StringBuffer();
    for (final k in keys) {
      sb.write(k);
      sb.write(params[k]);
    }
    sb.write(_secret);
    return md5.convert(utf8.encode(sb.toString())).toString();
  }

  /// Вход по логину/паролю. Возвращает true при успехе.
  Future<bool> login(String user, String password) async {
    if (!hasCredentials) return false;
    final params = <String, String>{
      'method': 'auth.getMobileSession',
      'username': user.trim(),
      'password': password,
      'api_key': _apiKey!,
    };
    params['api_sig'] = _sign(params);
    params['format'] = 'json';
    try {
      final r = await _dio.post(_base,
          data: params,
          options: Options(contentType: Headers.formUrlEncodedContentType));
      final sk = r.data['session']?['key'] as String?;
      final name = r.data['session']?['name'] as String?;
      if (sk == null) return false;
      _sessionKey = sk;
      _username = name ?? user.trim();
      await _storage.write(key: _kSessionKey, value: sk);
      await _storage.write(key: _kUsername, value: _username!);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    _sessionKey = null;
    _username = null;
    await _storage.delete(key: _kSessionKey);
    await _storage.delete(key: _kUsername);
  }

  Future<void> updateNowPlaying(Track t) =>
      _call('track.updateNowPlaying', {'artist': t.artist, 'track': t.title});

  Future<void> scrobble(Track t, int startedAtEpochSec) => _call(
      'track.scrobble',
      {
        'artist': t.artist,
        'track': t.title,
        'timestamp': '$startedAtEpochSec',
      });

  Future<void> _call(String method, Map<String, String> extra) async {
    if (!enabled) return;
    final params = <String, String>{
      'method': method,
      'api_key': _apiKey!,
      'sk': _sessionKey!,
      ...extra,
    };
    params['api_sig'] = _sign(params);
    params['format'] = 'json';
    try {
      await _dio.post(_base,
          data: params,
          options: Options(contentType: Headers.formUrlEncodedContentType));
    } catch (_) {/* скробблинг не критичен */}
  }

  // --- Read-методы графа похожести/тегов (Recs v2) ---
  // Нужен только API-ключ (без сессии/подписи): работают, даже если юзер не
  // залогинен в Last.fm, но ввёл ключ. Без ключа — движок опирается на
  // source/SC/YT-провайдеры (Q2).

  /// Доступны ли read-методы (есть непустой API-ключ).
  bool get hasApiKey => _apiKey?.isNotEmpty ?? false;

  Future<Map<String, dynamic>?> _read(Map<String, String> params) async {
    if (!hasApiKey) return null;
    try {
      final r = await _dio.get(_base, queryParameters: {
        ...params,
        'api_key': _apiKey!,
        'format': 'json',
      });
      return _asMap(r.data);
    } catch (_) {
      return null;
    }
  }

  /// track.getSimilar → похожие треки (artist/title/match 0..1).
  Future<List<({String artist, String title, double weight})>> getSimilarTracks(
      String artist, String title,
      {int limit = 30}) async {
    final j = await _read({
      'method': 'track.getsimilar',
      'artist': artist,
      'track': title,
      'autocorrect': '1',
      'limit': '$limit',
    });
    final list = _nodeList(_asMap(j?['similartracks'])?['track']);
    return [
      for (final m in list)
        (
          artist: _artistName(m),
          title: (m['name'] as String?) ?? '',
          weight: _toDouble(m['match']),
        )
    ].where((e) => e.artist.isNotEmpty && e.title.isNotEmpty).toList();
  }

  /// artist.getSimilar → похожие артисты.
  Future<List<({String name, double weight})>> getSimilarArtists(String artist,
      {int limit = 30}) async {
    final j = await _read({
      'method': 'artist.getsimilar',
      'artist': artist,
      'autocorrect': '1',
      'limit': '$limit',
    });
    final list = _nodeList(_asMap(j?['similarartists'])?['artist']);
    return [
      for (final m in list)
        (name: (m['name'] as String?) ?? '', weight: _toDouble(m['match']))
    ].where((e) => e.name.isNotEmpty).toList();
  }

  /// track.getTopTags → теги трека (lowercase).
  Future<List<String>> getTrackTopTags(String artist, String title,
          {int limit = 10}) async =>
      _tagNames(
        await _read({
          'method': 'track.gettoptags',
          'artist': artist,
          'track': title,
          'autocorrect': '1',
        }),
        limit,
      );

  /// artist.getTopTags → теги артиста (lowercase).
  Future<List<String>> getArtistTopTags(String artist, {int limit = 10}) async =>
      _tagNames(
        await _read({
          'method': 'artist.gettoptags',
          'artist': artist,
          'autocorrect': '1',
        }),
        limit,
      );

  /// tag.getTopArtists → артисты по тегу (для онбординга/exploration).
  Future<List<String>> getTagTopArtists(String tag, {int limit = 30}) async {
    final j = await _read({
      'method': 'tag.gettopartists',
      'tag': tag,
      'limit': '$limit',
    });
    final list = _nodeList(_asMap(j?['topartists'])?['artist']);
    return [for (final m in list) (m['name'] as String?) ?? '']
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// tag.getTopTracks → треки по тегу.
  Future<List<({String artist, String title})>> getTagTopTracks(String tag,
      {int limit = 30}) async {
    final j = await _read({
      'method': 'tag.gettoptracks',
      'tag': tag,
      'limit': '$limit',
    });
    final list = _nodeList(_asMap(j?['tracks'])?['track']);
    return [
      for (final m in list)
        (artist: _artistName(m), title: (m['name'] as String?) ?? '')
    ].where((e) => e.artist.isNotEmpty && e.title.isNotEmpty).toList();
  }

  /// artist.getTopTracks → популярные треки артиста (порядок = популярность).
  /// Для режима «Популярное» — хиты любимых артистов пользователя.
  Future<List<({String artist, String title})>> getArtistTopTracks(
      String artist,
      {int limit = 20}) async {
    final j = await _read({
      'method': 'artist.gettoptracks',
      'artist': artist,
      'autocorrect': '1',
      'limit': '$limit',
    });
    final list = _nodeList(_asMap(j?['toptracks'])?['track']);
    return [
      for (final m in list)
        (
          artist: _artistName(m).isEmpty ? artist : _artistName(m),
          title: (m['name'] as String?) ?? ''
        )
    ].where((e) => e.title.isNotEmpty).toList();
  }

  static List<String> _tagNames(Map<String, dynamic>? j, int limit) {
    final list = _nodeList(_asMap(j?['toptags'])?['tag']);
    return [
      for (final m in list) ((m['name'] as String?) ?? '').toLowerCase()
    ].where((s) => s.isNotEmpty).take(limit).toList();
  }

  static String _artistName(Map<String, dynamic> m) {
    final a = m['artist'];
    if (a is Map) return (a['name'] as String?) ?? '';
    if (a is String) return a;
    return '';
  }

  static double _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.isNotEmpty) {
      try {
        final d = jsonDecode(data);
        if (d is Map<String, dynamic>) return d;
      } catch (_) {}
    }
    return null;
  }

  /// Last.fm отдаёт объект вместо массива, когда результат один — нормализуем.
  static List<Map<String, dynamic>> _nodeList(Object? node) {
    if (node is List) {
      return [
        for (final e in node)
          if (e is Map<String, dynamic>) e
      ];
    }
    if (node is Map<String, dynamic>) return [node];
    return const [];
  }
}
