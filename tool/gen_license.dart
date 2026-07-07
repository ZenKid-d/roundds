// Генерация подписанного Premium-кода (для выдачи подписчику Boosty).
//
// Приватный seed берётся из переменной окружения ROUNDDS_PRIV (base64url),
// чтобы не хранить ключ в файлах и истории команд.
//
// Пример:
//   export ROUNDDS_PRIV=<seed из premium_keygen.dart>
//   dart run tool/gen_license.dart --days 30 --owner "Иван И."
//
// Печатает готовый код вида RD1.<payload>.<signature> — его отправляешь
// подписчику, он вставляет код на экране Premium.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

String _b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');

List<int> _b64uDecode(String s) {
  final pad = (4 - s.length % 4) % 4;
  return base64Url.decode(s + ('=' * pad));
}

Future<void> main(List<String> args) async {
  final seedB64 = Platform.environment['ROUNDDS_PRIV'];
  if (seedB64 == null || seedB64.isEmpty) {
    stderr.writeln('Нет приватного ключа. Сначала:');
    stderr.writeln('  export ROUNDDS_PRIV=<seed из premium_keygen.dart>');
    exit(1);
  }

  var days = 30;
  var owner = '';
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--days') days = int.parse(args[i + 1]);
    if (args[i] == '--owner') owner = args[i + 1];
  }

  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(_b64uDecode(seedB64));

  final exp =
      DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch ~/ 1000;
  final payload = <String, dynamic>{'v': 1, 'exp': exp};
  if (owner.isNotEmpty) payload['own'] = owner;

  final message = utf8.encode(jsonEncode(payload));
  final signature = await algorithm.sign(message, keyPair: keyPair);
  final code = 'RD1.${_b64u(message)}.${_b64u(signature.bytes)}';

  final until = DateTime.now().add(Duration(days: days));
  stderr.writeln('Срок: $days дн. (до ${until.toIso8601String().split('T')[0]})'
      '${owner.isEmpty ? '' : ', владелец: $owner'}');
  stdout.writeln(code);
}
