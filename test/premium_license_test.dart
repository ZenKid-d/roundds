import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/core/premium/license.dart';

void main() {
  // Реальный код, подписанный ключом из premium_config.dart (kPremiumPublicKey),
  // срок — до 2100 года, владелец «Test User».
  const sample =
      'RD1.eyJ2IjoxLCJleHAiOjQxMDI0NDQ4MDAsIm93biI6IlRlc3QgVXNlciJ9'
      '.gjtAbukJKcuSzZh8b1uYpKioZinHsFt-ColX2kaqxA1KKpSsKsdLBt6V7DWwbj9CBMi1Mvl3x8l-MdvXmwmpCA';

  final verifier = LicenseVerifier();

  // Код, привязанный к устройству "DEVICE-A" (тот же ключ, срок до 2100).
  const deviceCode =
      'RD1.eyJ2IjoxLCJleHAiOjQxMDI0NDQ4MDAsImRldiI6IkRFVklDRS1BIn0'
      '.xcureHPdsxGOMabNGAhU_fvmotp5sRQorF6HNTpogMBKFH1P3FiSUDuOzsj1dQJ8eOG_Pf7SHKIxgckM0W6rBg';

  test('валидный код проходит проверку', () async {
    final payload = await verifier.verify(sample);
    expect(payload, isNotNull);
    expect(payload!.owner, 'Test User');
    expect(payload.device, isNull); // не привязан — работает везде
    expect(payload.isExpired, isFalse);
    expect(payload.expiry.year, 2100);
  });

  test('код с привязкой к устройству отдаёт device', () async {
    final payload = await verifier.verify(deviceCode);
    expect(payload, isNotNull);
    expect(payload!.device, 'DEVICE-A');
  });

  test('подделанная подпись отклоняется', () async {
    final parts = sample.split('.');
    final sig = parts[2];
    final flipped = (sig[0] == 'A' ? 'B' : 'A') + sig.substring(1);
    final tampered = '${parts[0]}.${parts[1]}.$flipped';
    expect(await verifier.verify(tampered), isNull);
  });

  test('подменённый payload отклоняется', () async {
    // тот же payload-контейнер, но другой exp (подпись не сойдётся)
    final parts = sample.split('.');
    final forged = 'RD1.eyJ2IjoxLCJleHAiOjk5OTk5OTk5OTl9.${parts[2]}';
    expect(await verifier.verify(forged), isNull);
  });

  test('мусор и неверный формат отклоняются', () async {
    expect(await verifier.verify('не код'), isNull);
    expect(await verifier.verify(''), isNull);
    expect(await verifier.verify('RD1.abc.def'), isNull);
    expect(await verifier.verify('XX1.$sample'), isNull);
  });

  test('LicensePayload.isExpired считает срок корректно', () {
    expect(LicensePayload(expiry: DateTime(2000)).isExpired, isTrue);
    expect(LicensePayload(expiry: DateTime(2100)).isExpired, isFalse);
  });
}
