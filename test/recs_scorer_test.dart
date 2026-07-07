import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/data/recs/scorer.dart';
import 'package:roundds/data/recs/taste_profile.dart';

void main() {
  const profile = TasteProfile(
    longArtists: {'loved': 3.0, 'meh': 0.2},
    negArtists: {'hated': 3.0},
    heardArtists: {'loved', 'meh', 'hated'},
  );

  group('Scorer (balanced)', () {
    const s = Scorer(profile);

    test('любимый знакомый артист > незнакомого', () {
      expect(
        s.score(const ScoreCandidate(artistKey: 'loved')),
        greaterThan(s.score(const ScoreCandidate(artistKey: 'brand_new'))),
      );
    });

    test('негативный артист ниже нейтрального нового', () {
      expect(
        s.score(const ScoreCandidate(artistKey: 'hated')),
        lessThan(s.score(const ScoreCandidate(artistKey: 'brand_new'))),
      );
    });

    test('novelty: незнакомый артист получает положительный вклад', () {
      expect(s.score(const ScoreCandidate(artistKey: 'unknown')), greaterThan(0));
    });

    test('repetition penalty: только что звучал ниже, чем давно', () {
      final justPlayed =
          s.score(const ScoreCandidate(artistKey: 'loved', lastPlayedSecAgo: 0));
      final longAgo = s.score(
          const ScoreCandidate(artistKey: 'loved', lastPlayedSecAgo: 7 * 86400));
      expect(justPlayed, lessThan(longAgo));
    });
  });

  group('Scorer (пресеты характера)', () {
    test('«Незнакомое» поднимает нового выше знакомого слабого', () {
      const s = Scorer(profile, weights: ScoreWeights.unfamiliar);
      expect(
        s.score(const ScoreCandidate(artistKey: 'brand_new')),
        greaterThan(s.score(const ScoreCandidate(artistKey: 'meh'))),
      );
    });

    test('«Популярное» ценит популярность', () {
      const s = Scorer(profile, weights: ScoreWeights.popular);
      expect(
        s.score(const ScoreCandidate(artistKey: 'x', popularity: 1.0)),
        greaterThan(s.score(const ScoreCandidate(artistKey: 'y', popularity: 0.0))),
      );
    });

    test('«Любимое» ценит знакомого сильнее, чем «Незнакомое»', () {
      const fav = Scorer(profile, weights: ScoreWeights.favorite);
      const unf = Scorer(profile, weights: ScoreWeights.unfamiliar);
      expect(
        fav.score(const ScoreCandidate(artistKey: 'loved')),
        greaterThan(unf.score(const ScoreCandidate(artistKey: 'loved'))),
      );
    });
  });
}
