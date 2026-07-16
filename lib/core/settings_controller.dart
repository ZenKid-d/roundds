import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/aggregator.dart';
import '../data/sources/soundcloud_source.dart';
import '../data/sources/vk_source.dart';
import '../data/sources/yandex_source.dart';
import '../domain/models/source_type.dart';

/// Пользовательские настройки: включённые источники, токены Яндекса/SoundCloud/VK.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required SharedPreferences prefs,
    required FlutterSecureStorage secure,
    required YandexSource yandex,
    required SoundcloudSource soundcloud,
    required VkSource vk,
    required Aggregator aggregator,
  })  : _prefs = prefs,
        _secure = secure,
        _yandex = yandex,
        _soundcloud = soundcloud,
        _vk = vk,
        _aggregator = aggregator;

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  final YandexSource _yandex;
  final SoundcloudSource _soundcloud;
  final VkSource _vk;
  final Aggregator _aggregator;

  Set<SourceType> _enabled = SourceType.values.toSet();
  String? _yandexToken;
  String? _soundcloudToken;
  String? _vkToken;

  Set<SourceType> get enabledSources => _enabled;
  bool isEnabled(SourceType t) => _enabled.contains(t);
  String? get yandexToken => _yandexToken;
  bool get hasYandexToken => (_yandexToken ?? '').isNotEmpty;
  String? get soundcloudToken => _soundcloudToken;
  bool get hasSoundcloudToken => (_soundcloudToken ?? '').isNotEmpty;
  String? get vkToken => _vkToken;
  bool get hasVkToken => (_vkToken ?? '').isNotEmpty;

  /// Обход блокировок DNS (DoH). Применяется при старте (клиенты строятся один
  /// раз), поэтому смена требует перезапуска приложения.
  bool get dohEnabled => _prefs.getBool('doh_enabled') ?? false;
  Future<void> setDohEnabled(bool on) async {
    await _prefs.setBool('doh_enabled', on);
    notifyListeners();
  }

  Future<void> load() async {
    final raw = _prefs.getStringList('enabled_sources');
    if (raw != null) {
      _enabled = raw.map(SourceTypeX.fromId).toSet();
    }
    _yandexToken = await _secure.read(key: 'yandex_token');
    _yandex.setToken(_yandexToken);
    _soundcloudToken = await _secure.read(key: 'soundcloud_token');
    _soundcloud.setToken(_soundcloudToken);
    _vkToken = await _secure.read(key: 'vk_token');
    _vk.setToken(_vkToken);
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

  Future<void> setVkToken(String? token) async {
    _vkToken = token;
    if (token == null || token.isEmpty) {
      await _secure.delete(key: 'vk_token');
    } else {
      await _secure.write(key: 'vk_token', value: token);
    }
    _vk.setToken(_vkToken);
    notifyListeners();
  }
}
