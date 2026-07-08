import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'premium_config.dart';

/// Данные, зашитые в подписанный Premium-код.
class LicensePayload {
  const LicensePayload({required this.expiry, this.owner, this.device});

  /// Срок действия подписки.
  final DateTime expiry;

  /// Имя/метка владельца (мягкий антишеринг), может быть пустым.
  final String? owner;

  /// ID устройства, к которому привязан код. null — код работает везде.
  final String? device;

  bool get isExpired => DateTime.now().isAfter(expiry);
}

/// Оффлайн-проверка Premium-кодов подписью Ed25519.
///
/// Приватный ключ — только у владельца проекта (см. tool/gen_license.dart);
/// в приложение зашит лишь ПУБЛИЧНЫЙ ключ, поэтому код нельзя подделать и не
/// нужен сервер. Формат кода:
///   `RD1.<base64url(payload)>.<base64url(signature)>`
/// где payload — компактный JSON `{"v":1,"exp":<unix_sec>,"own":"..."}`.
class LicenseVerifier {
  LicenseVerifier({String publicKeyBase64 = kPremiumPublicKey})
      : _publicKey = SimplePublicKey(
          b64uDecode(publicKeyBase64),
          type: KeyPairType.ed25519,
        );

  static final Ed25519 _algorithm = Ed25519();
  final SimplePublicKey _publicKey;

  /// Возвращает payload, если код корректно подписан нашим ключом; иначе null.
  /// Срок НЕ проверяет — это делает вызывающий, чтобы отличать «поддельный»
  /// код от «просроченного».
  Future<LicensePayload?> verify(String rawCode) async {
    final parts = rawCode.trim().split('.');
    if (parts.length != 3 || parts[0] != 'RD1') return null;

    final List<int> payloadBytes;
    final List<int> sigBytes;
    try {
      payloadBytes = b64uDecode(parts[1]);
      sigBytes = b64uDecode(parts[2]);
    } catch (_) {
      return null;
    }
    if (sigBytes.length != 64) return null;

    final ok = await _algorithm.verify(
      payloadBytes,
      signature: Signature(sigBytes, publicKey: _publicKey),
    );
    if (!ok) return null;

    try {
      final map =
          jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
      final exp = (map['exp'] as num).toInt();
      final own = (map['own'] as String?)?.trim();
      final dev = (map['dev'] as String?)?.trim();
      return LicensePayload(
        expiry: DateTime.fromMillisecondsSinceEpoch(exp * 1000),
        owner: (own == null || own.isEmpty) ? null : own,
        device: (dev == null || dev.isEmpty) ? null : dev,
      );
    } catch (_) {
      return null;
    }
  }
}

/// base64url-декодирование, терпимое к отсутствию паддинга.
List<int> b64uDecode(String s) {
  final pad = (4 - s.length % 4) % 4;
  return base64Url.decode(s + ('=' * pad));
}
