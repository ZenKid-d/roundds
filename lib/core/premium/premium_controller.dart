import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'license.dart';

/// Результат активации кода — для сообщений в UI.
enum RedeemResult { ok, invalid, expired }

/// Состояние Premium. Хранит активированный код в secure storage и
/// перепроверяет его подпись и срок при каждом запуске (без сервера).
class PremiumController extends ChangeNotifier {
  PremiumController(this._secure, {LicenseVerifier? verifier})
      : _verifier = verifier ?? LicenseVerifier();

  static const String _key = 'premium_code';

  final FlutterSecureStorage _secure;
  final LicenseVerifier _verifier;

  LicensePayload? _license;
  String? _code;

  /// Premium активен только если код валиден и не просрочен.
  bool get isPremium => _license != null && !_license!.isExpired;

  /// Есть сохранённый код, но он уже просрочен (для подсказки «продлите»).
  bool get isExpired => _license != null && _license!.isExpired;

  DateTime? get expiry => _license?.expiry;
  String? get owner => _license?.owner;

  /// Сырой активированный код (для «Копировать» / переноса на другое устройство).
  String? get code => _code;

  /// Загрузить и перепроверить сохранённый код при старте.
  Future<void> load() async {
    final code = await _secure.read(key: _key);
    if (code == null) return;
    _code = code;
    // Просроченный код тоже держим (покажем «истёк»), но isPremium=false.
    _license = await _verifier.verify(code);
    notifyListeners();
  }

  /// Активировать введённый код.
  Future<RedeemResult> redeem(String code) async {
    final trimmed = code.trim();
    final payload = await _verifier.verify(trimmed);
    if (payload == null) return RedeemResult.invalid;
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
