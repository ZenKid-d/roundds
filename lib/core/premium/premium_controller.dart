import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_id.dart';
import 'license.dart';

/// Результат активации кода — для сообщений в UI.
enum RedeemResult { ok, invalid, expired, wrongDevice }

/// Состояние Premium. Хранит активированный код в secure storage и
/// перепроверяет его подпись, срок и привязку к устройству при каждом
/// запуске (без сервера).
class PremiumController extends ChangeNotifier {
  PremiumController(this._secure, this._deviceIdSource,
      {LicenseVerifier? verifier})
      : _verifier = verifier ?? LicenseVerifier();

  static const String _key = 'premium_code';

  final FlutterSecureStorage _secure;
  final DeviceId _deviceIdSource;
  final LicenseVerifier _verifier;

  LicensePayload? _license;
  String? _code;
  String? _deviceId;

  /// ID этого устройства (для привязки кода). Доступен после load().
  String? get deviceId => _deviceId;

  /// Premium активен только если код валиден и не просрочен.
  bool get isPremium => _license != null && !_license!.isExpired;

  /// Есть сохранённый код, но он уже просрочен (для подсказки «продлите»).
  bool get isExpired => _license != null && _license!.isExpired;

  DateTime? get expiry => _license?.expiry;
  String? get owner => _license?.owner;

  /// Сырой активированный код (для «Копировать» / переноса на другое устройство).
  String? get code => _code;

  /// Код привязан к другому устройству и здесь не действует.
  bool _wrongDevice(LicensePayload p) =>
      p.device != null && p.device != _deviceId;

  /// Загрузить и перепроверить сохранённый код при старте.
  Future<void> load() async {
    _deviceId = await _deviceIdSource.get();
    final code = await _secure.read(key: _key);
    if (code == null) {
      notifyListeners();
      return;
    }
    _code = code;
    final payload = await _verifier.verify(code);
    // Код для другого устройства Premium не даёт.
    _license = (payload != null && !_wrongDevice(payload)) ? payload : null;
    notifyListeners();
  }

  /// Активировать введённый код.
  Future<RedeemResult> redeem(String code) async {
    _deviceId ??= await _deviceIdSource.get();
    final trimmed = code.trim();
    final payload = await _verifier.verify(trimmed);
    if (payload == null) return RedeemResult.invalid;
    if (_wrongDevice(payload)) return RedeemResult.wrongDevice;
    if (payload.isExpired) return RedeemResult.expired;
    await _secure.write(key: _key, value: trimmed);
    _code = trimmed;
    _license = payload;
    notifyListeners();
    return RedeemResult.ok;
  }

  /// Отвязать код на этом устройстве.
  Future<void> clear() async {
    await _secure.delete(key: _key);
    _license = null;
    _code = null;
    notifyListeners();
  }
}
