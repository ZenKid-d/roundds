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

  group('RecsDedup fuzzy', () {
    test('tokenSimilarity: тот же набор слов = 1', () {
      expect(RecsDedup.tokenSimilarity('hello world', 'world hello'), 1.0);
    });

    test('levenshteinRatio: опечатка на 1 символ высока', () {
      expect(RecsDedup.levenshteinRatio('beyonce', 'beyonse'), greaterThan(0.8));
    });

    test('isFuzzyDuplicate: точный ключ (radio edit вырезан)', () {
      expect(
        RecsDedup.isFuzzyDuplicate(
            'Daft Punk', 'Get Lucky', 'Daft Punk', 'Get Lucky (Radio Edit)'),
        isTrue,
      );
    });

    test('isFuzzyDuplicate: разные треки одного артиста — не дубликат', () {
      expect(
        RecsDedup.isFuzzyDuplicate(
            'Daft Punk', 'Get Lucky', 'Daft Punk', 'Instant Crush'),
        isFalse,
      );
    });

    test('isFuzzyDuplicate: разные артисты — не дубликат', () {
      expect(
        RecsDedup.isFuzzyDuplicate('Artist X', 'Song', 'Artist Y', 'Song'),
        isFalse,
      );
    });
  });

  group('RecsDedup.resolvesTo (проверка верности резолва)', () {
    test('точное совпадение (ремастер вырезан)', () {
      expect(
          RecsDedup.resolvesTo('Radiohead', 'Karma Police', 'Radiohead',
              'Karma Police (Remastered)'),
          isTrue);
    });
    test('feat в резолве не мешает', () {
      expect(
          RecsDedup.resolvesTo('Drake', 'Money In The Grave', 'Drake, Rick Ross',
              'Money In The Grave'),
          isTrue);
    });
    test('чужой артист (кавер) — не тот трек', () {
      expect(RecsDedup.resolvesTo('Bon Iver', 'Skinny Love', 'Birdy', 'Skinny Love'),
          isFalse);
    });
    test('другое название — не тот трек', () {
      expect(RecsDedup.resolvesTo('Radiohead', 'Karma Police', 'Radiohead', 'Creep'),
          isFalse);
    });
  });
}
