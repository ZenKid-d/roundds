import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Стабильный идентификатор установки — под него привязывается Premium-код.
///
/// Генерируется один раз (криптослучайные 16 байт) и хранится в secure
/// storage: переживает перезапуск и обновление приложения. При ПЕРЕустановке
/// создаётся новый — тогда нужен новый код (это и есть «одно устройство»).
class DeviceId {
  DeviceId(this._secure);

  static const String _key = 'device_id';

  final FlutterSecureStorage _secure;
  String? _cached;

  Future<String> get() async {
    if (_cached != null) return _cached!;
    var id = await _secure.read(key: _key);
    if (id == null || id.isEmpty) {
      final rnd = Random.secure();
      final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
      id = base64Url.encode(bytes).replaceAll('=', '');
      await _secure.write(key: _key, value: id);
    }
    _cached = id;
    return id;
  }
}
