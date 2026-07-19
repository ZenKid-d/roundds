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

  group('RecsDedup.matchScore (скоринг с учётом длительности)', () {
    test('точное совпадение с той же длительностью — высокий счёт', () {
      final s = RecsDedup.matchScore(
        wantArtist: 'Radiohead',
        wantTitle: 'Karma Police',
        gotArtist: 'Radiohead',
        gotTitle: 'Karma Police',
        wantDuration: const Duration(minutes: 4, seconds: 21),
        gotDuration: const Duration(minutes: 4, seconds: 21),
      );
      expect(s, isNotNull);
      expect(s!, greaterThan(0.95));
    });

    test('ремастер/feat не мешают, близкая длительность проходит', () {
      final s = RecsDedup.matchScore(
        wantArtist: 'Drake',
        wantTitle: 'Money In The Grave',
        gotArtist: 'Drake, Rick Ross',
        gotTitle: 'Money In The Grave',
        wantDuration: const Duration(minutes: 3, seconds: 10),
        gotDuration: const Duration(minutes: 3, seconds: 15),
      );
      expect(s, isNotNull);
      expect(s!, greaterThan(0.8));
    });

    test('кавер той же длительности отсечён по артисту', () {
      // Bon Iver «Skinny Love» vs кавер Birdy — даже при той же длине и названии
      // артист слишком далёк, кавер не должен пройти.
      final s = RecsDedup.matchScore(
        wantArtist: 'Bon Iver',
        wantTitle: 'Skinny Love',
        gotArtist: 'Birdy',
        gotTitle: 'Skinny Love',
        wantDuration: const Duration(minutes: 3, seconds: 55),
        gotDuration: const Duration(minutes: 3, seconds: 55),
      );
      expect(s, isNull);
    });

    test('полная версия предпочтительнее радио-эдита — оба проходят', () {
      // Полный трек (Δ=0) набирает больше, чем радио-эдит (Δ=60с → штраф 0.2).
      final full = RecsDedup.matchScore(
        wantArtist: 'Daft Punk',
        wantTitle: 'Get Lucky',
        gotArtist: 'Daft Punk',
        gotTitle: 'Get Lucky',
        wantDuration: const Duration(minutes: 6, seconds: 9),
        gotDuration: const Duration(minutes: 6, seconds: 9),
      )!;
      final radioEdit = RecsDedup.matchScore(
        wantArtist: 'Daft Punk',
        wantTitle: 'Get Lucky',
        gotArtist: 'Daft Punk',
        gotTitle: 'Get Lucky',
        wantDuration: const Duration(minutes: 6, seconds: 9),
        gotDuration: const Duration(minutes: 4, seconds: 0), // radio edit
      );
      expect(radioEdit, isNotNull, reason: 'радио-эдит всё ещё та же песня');
      expect(full, greaterThan(radioEdit!));
    });

    test('30-сек сниппет против полного трека — дисквалификация по ratio', () {
      // Полный 3:20 (200с) против сниппета 0:30 — ratio 0.15 < 0.5 → 0.2 по
      // длительности; но название/артист точные, так что проходит, но с низким
      // счётом. Это намеренно: сниппет хуже полной версии, ранжируется ниже.
      final full = RecsDedup.matchScore(
        wantArtist: 'The Weeknd',
        wantTitle: 'Blinding Lights',
        gotArtist: 'The Weeknd',
        gotTitle: 'Blinding Lights',
        wantDuration: const Duration(minutes: 3, seconds: 20),
        gotDuration: const Duration(minutes: 3, seconds: 20),
      )!;
      final snip = RecsDedup.matchScore(
        wantArtist: 'The Weeknd',
        wantTitle: 'Blinding Lights',
        gotArtist: 'The Weeknd',
        gotTitle: 'Blinding Lights',
        wantDuration: const Duration(minutes: 3, seconds: 20),
        gotDuration: const Duration(seconds: 30),
      )!;
      expect(full, greaterThan(snip));
      expect(snip, lessThan(0.85));
    });

    test('отсутствие длительности — нейтрально, не дисквалифицирует', () {
      final s = RecsDedup.matchScore(
        wantArtist: 'Radiohead',
        wantTitle: 'Karma Police',
        gotArtist: 'Radiohead',
        gotTitle: 'Karma Police',
        // duration не передан — трек не должен провалиться только из-за этого
      );
      expect(s, isNotNull);
      expect(s!, greaterThan(0.8));
    });

    test('чужое название — null независимо от длительности', () {
      final s = RecsDedup.matchScore(
        wantArtist: 'Radiohead',
        wantTitle: 'Karma Police',
        gotArtist: 'Radiohead',
        gotTitle: 'Creep',
        wantDuration: const Duration(minutes: 4),
        gotDuration: const Duration(minutes: 4),
      );
      expect(s, isNull);
    });
  });
}
