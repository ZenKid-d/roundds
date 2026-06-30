import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/aggregator.dart';
import '../data/sources/soundcloud_source.dart';
import '../data/sources/yandex_source.dart';
import '../domain/models/source_type.dart';

/// Пользовательские настройки: включённые источники, токены Яндекса/SoundCloud.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required SharedPreferences prefs,
    required FlutterSecureStorage secure,
    required YandexSource yandex,
    required SoundcloudSource soundcloud,
    required Aggregator aggregator,
  })  : _prefs = prefs,
        _secure = secure,
        _yandex = yandex,
        _soundcloud = soundcloud,
        _aggregator = aggregator;

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  final YandexSource _yandex;
  final SoundcloudSource _soundcloud;
  final Aggregator _aggregator;

  Set<SourceType> _enabled = SourceType.values.toSet();
  String? _yandexToken;
  String? _soundcloudToken;

  Set<SourceType> get enabledSources => _enabled;
  bool isEnabled(SourceType t) => _enabled.contains(t);
  String? get yandexToken => _yandexToken;
  bool get hasYandexToken => (_yandexToken ?? '').isNotEmpty;
  String? get soundcloudToken => _soundcloudToken;
  bool get hasSoundcloudToken => (_soundcloudToken ?? '').isNotEmpty;

  Future<void> load() async {
    final raw = _prefs.getStringList('enabled_sources');
    if (raw != null) {
      _enabled = raw.map(SourceTypeX.fromId).toSet();
    }
    _yandexToken = await _secure.read(key: 'yandex_token');
    _yandex.setToken(_yandexToken);
    _soundcloudToken = await _secure.read(key: 'soundcloud_token');
    _soundcloud.setToken(_soundcloudToken);
    _aggregator.setEnabled(_enabled);
    notifyListeners();
  }

  Future<void> toggleSource(SourceType t, bool on) async {
    if (on) {
      _enabled.add(t);
    } else {
      _enabled.remove(t);
    }
    await _prefs.setStringList(
        'enabled_sources', _enabled.map((e) => e.id).toList());
    _aggregator.setEnabled(_enabled);
    notifyListeners();
  }

  Future<void> setYandexToken(String? token) async {
    _yandexToken = token;
    if (token == null || token.isEmpty) {
      await _secure.delete(key: 'yandex_token');
    } else {
      await _secure.write(key: 'yandex_token', value: token);
    }
    _yandex.setToken(_yandexToken);
    notifyListeners();
  }

  Future<void> setSoundcloudToken(String? token) async {
    _soundcloudToken = token;
    if (token == null || token.isEmpty) {
      await _secure.delete(key: 'soundcloud_token');
    } else {
      await _secure.write(key: 'soundcloud_token', value: token);
    }
    _soundcloud.setToken(_soundcloudToken);
    notifyListeners();
  }
}
