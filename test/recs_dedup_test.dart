import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/data/recs/recs_dedup.dart';

void main() {
  group('RecsDedup.normKey', () {
    test('один трек с разным оформлением → один ключ', () {
      final a =
          RecsDedup.normKey('The Weeknd', 'Blinding Lights (Remastered)');
      final b = RecsDedup.normKey('the weeknd', 'Blinding Lights');
      expect(a, b);
    });

    test('feat вырезается', () {
      final a =
          RecsDedup.normKey('Drake', 'Money In The Grave (feat. Rick Ross)');
      final b = RecsDedup.normKey('Drake', 'Money In The Grave');
      expect(a, b);
    });

    test('разные треки — разные ключи', () {
      expect(
        RecsDedup.normKey('Artist', 'Song X') ==
            RecsDedup.normKey('Artist', 'Song Y'),
        isFalse,
      );
    });
  });

  group('RecsDedup.normalize', () {
    test('диакритика', () {
      expect(RecsDedup.normalize('Beyoncé'), RecsDedup.normalize('Beyonce'));
    });

    test('пунктуация и лишние пробелы', () {
      expect(RecsDedup.normalize('  Hello,  World! '), 'hello world');
    });

    test('скобочный тег (Live) убирается', () {
      expect(RecsDedup.normalize('Bohemian Rhapsody (Live)'),
          RecsDedup.normalize('Bohemian Rhapsody'));
    });
  });
}
