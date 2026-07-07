// Генерация пары ключей Ed25519 для Premium-кодов.
//
// Запуск:  dart run tool/premium_keygen.dart
//
// Публичный ключ вставь в lib/core/premium/premium_config.dart
// (константа kPremiumPublicKey). Приватный seed сохрани В ТАЙНЕ и НЕ коммить —
// им подписываются коды доступа (tool/gen_license.dart).
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

String _b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');

Future<void> main() async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final seed = await keyPair.extractPrivateKeyBytes(); // 32-байтный seed
  final publicKey = await keyPair.extractPublicKey();

  print('=== ПУБЛИЧНЫЙ КЛЮЧ (в приложение) ===');
  print('lib/core/premium/premium_config.dart → kPremiumPublicKey:');
  print('  ${_b64u(publicKey.bytes)}');
  print('');
  print('=== ПРИВАТНЫЙ SEED (храни в тайне, НЕ коммить!) ===');
  print('Для подписи кодов: export ROUNDDS_PRIV=<этот seed>');
  print('  ${_b64u(seed)}');
}
