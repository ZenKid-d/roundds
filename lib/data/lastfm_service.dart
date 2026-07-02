import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/track.dart';

/// Скробблинг в Last.fm. Пользователь создаёт API-аккаунт (key+secret) и входит
/// логином/паролем (auth.getMobileSession) — пароль не сохраняется, хранится
/// только session key.
class LastfmService {
  LastfmService(this._dio, this._prefs) {
    _apiKey = _prefs.getString('lastfm_key');
    _secret = _prefs.getString('lastfm_secret');
    _sessionKey = _prefs.getString('lastfm_sk');
    _username = _prefs.getString('lastfm_user');
  }

  final Dio _dio;
  final SharedPreferences _prefs;
  static const _base = 'https://ws.audioscrobbler.com/2.0/';

  String? _apiKey;
  String? _secret;
  String? _sessionKey;
  String? _username;

  bool get enabled => _sessionKey != null && _apiKey != null;
  bool get hasCredentials =>
      (_apiKey?.isNotEmpty ?? false) && (_secret?.isNotEmpty ?? false);
  String? get username => _username;

  Future<void> saveCredentials(String apiKey, String secret) async {
    _apiKey = apiKey.trim();
    _secret = secret.trim();
    await _prefs.setString('lastfm_key', _apiKey!);
    await _prefs.setString('lastfm_secret', _secret!);
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
      await _prefs.setString('lastfm_sk', sk);
      await _prefs.setString('lastfm_user', _username!);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    _sessionKey = null;
    _username = null;
    await _prefs.remove('lastfm_sk');
    await _prefs.remove('lastfm_user');
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
}
