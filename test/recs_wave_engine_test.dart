import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/data/recs/recs_dedup.dart';
import 'package:roundds/data/recs/scorer.dart';
import 'package:roundds/data/recs/taste_profile.dart';
import 'package:roundds/data/recs/wave_constraints.dart';
import 'package:roundds/data/recs/wave_engine.dart';
import 'package:roundds/domain/models/source_type.dart';
import 'package:roundds/domain/models/track.dart';

WaveCandidate _wc(String artist, String title,
        {List<String> tags = const [], double pop = 0}) =>
    WaveCandidate(
      Track(
          id: '$artist::$title',
          title: title,
          artist: artist,
          source: SourceType.soundcloud),
      tags: tags,
      popularity: pop,
    );

List<Track> _rank(
  List<WaveCandidate> cands, {
  TasteProfile profile = TasteProfile.empty,
  Map<String, int> cooldown = const {},
  Set<String> disliked = const {},
  ScoreWeights weights = ScoreWeights.balanced,
  WaveConstraints constraints = WaveConstraints.balanced,
  List<String> recent = const [],
  Set<String> served = const {},
  int limit = 18,
}) =>
    WaveEngine.rankWave(
      cands,
      profile: profile,
      cooldown: cooldown,
      dislikedKeys: disliked,
      weights: weights,
      constraints: constraints,
      recentArtists: recent,
      servedKeys: served,
      nowSec: 0,
      limit: limit,
    );

void main() {
  group('WaveEngine.rankWave — фильтры', () {
    test('дизлайкнутый трек не попадает в волну', () {
      final out = _rank(
        [_wc('A', 's1'), _wc('B', 's2'), _wc('C', 's3')],
        disliked: {RecsDedup.normKey('B', 's2')},
      );
      expect(out.any((t) => t.artist == 'B'), isFalse);
      expect(out.length, 2);
    });

    test('уже выданный трек (servedKeys) исключается', () {
      final out = _rank(
        [_wc('A', 's1'), _wc('B', 's2')],
        served: {RecsDedup.normKey('A', 's1')},
      );
      expect(out.any((t) => t.title == 's1'), isFalse);
    });
  });

  group('WaveEngine.rankWave — anti-repetition', () {
    test('один артист не чаще, чем раз в 5 позиций', () {
      final cands = <WaveCandidate>[];
      for (var i = 0; i < 12; i++) {
        cands.add(_wc('A', 'a$i'));
      }
      for (final a in ['B', 'C', 'D', 'E', 'F']) {
        for (var i = 0; i < 6; i++) {
          cands.add(_wc(a, '$a$i'));
        }
      }
      final out = _rank(cands,
          constraints:
              const WaveConstraints(minArtistGap: 5, maxPerArtistSession: 100),
          limit: 20);
      final artists = [for (final t in out) t.artist];
      for (var i = 0; i < artists.length; i++) {
        for (var j = i + 1; j < artists.length && j < i + 5; j++) {
          expect(artists[i] == artists[j], isFalse,
              reason: '${artists[i]} повторился в пределах 5 позиций');
        }
      }
    });
  });

  group('WaveEngine.rankWave — exploration', () {
    // 10 знакомых артистов (по одному треку) + 10 незнакомых, все разные.
    List<WaveCandidate> pool() => [
          for (var i = 0; i < 10; i++) _wc('Known$i', 'ks$i'),
          for (var i = 0; i < 10; i++) _wc('Unk$i', 'us$i'),
        ];
    final profile = TasteProfile(
      longArtists: {for (var i = 0; i < 10; i++) 'known$i': 3.0},
      heardArtists: {for (var i = 0; i < 10; i++) 'known$i'},
    );

    test('дефолт (Баланс): ≥15% незнакомых артистов', () {
      final out = _rank(pool(),
          profile: profile, weights: ScoreWeights.balanced, limit: 12);
      final unknown = out.where((t) => t.artist.startsWith('Unk')).length;
      expect(unknown / out.length, greaterThanOrEqualTo(0.15));
    });

    test('«Незнакомое»: большинство — незнакомые артисты', () {
      final out = _rank(pool(),
          profile: profile, weights: ScoreWeights.unfamiliar, limit: 12);
      final unknown = out.where((t) => t.artist.startsWith('Unk')).length;
      expect(unknown / out.length, greaterThan(0.5));
    });
  });

  group('Real-time адаптация (сессионные оверрайды)', () {
    test('скип топит направление: артист падает ниже незнакомого', () {
      const profile =
          TasteProfile(longArtists: {'liked': 3.0}, heardArtists: {'liked'});
      final adapted = profile.withSessionOverrides({'liked': -5.0});
      const base = Scorer(profile);
      final adaptedScorer = Scorer(adapted);

      final likedBase = base.score(const ScoreCandidate(artistKey: 'liked'));
      final likedAdapted =
          adaptedScorer.score(const ScoreCandidate(artistKey: 'liked'));
      expect(likedAdapted, lessThan(likedBase));

      final fresh = adaptedScorer.score(const ScoreCandidate(artistKey: 'fresh'));
      expect(fresh, greaterThan(likedAdapted));
    });
  });

  group('WaveEngine.looksLikeMusic (фильтр не-музыки)', () {
    Track track(int? sec) => Track(
          id: '${sec ?? -1}',
          title: 'x',
          artist: 'y',
          source: SourceType.soundcloud,
          duration: sec == null ? null : Duration(seconds: sec),
        );
    test('трек 3 минуты — музыка',
        () => expect(WaveEngine.looksLikeMusic(track(180)), isTrue));
    test('часовой микс — не музыка',
        () => expect(WaveEngine.looksLikeMusic(track(3600)), isFalse));
    test('шортс/клип 20 сек — не музыка',
        () => expect(WaveEngine.looksLikeMusic(track(20)), isFalse));
    test('неизвестная длительность — оставляем',
        () => expect(WaveEngine.looksLikeMusic(track(null)), isTrue));
  });

  group('WaveEngine.rankWave — настроение', () {
    test('кандидат с mood-тегом ранжируется выше такого же без тега', () {
      final out = WaveEngine.rankWave(
        [_wc('B', 's2'), _wc('A', 's1', tags: ['chill'])],
        profile: TasteProfile.empty,
        cooldown: const {},
        dislikedKeys: const {},
        weights: ScoreWeights.balanced,
        constraints: WaveConstraints.balanced,
        recentArtists: const [],
        servedKeys: const {},
        nowSec: 0,
        moodTags: const {'chill'},
        limit: 10,
      );
      expect(out.first.artist, 'A');
    });
  });

  group('WaveEngine.rankWave — популярное', () {
    test('в режиме «Популярное» популярный кандидат впереди непопулярного', () {
      final out = WaveEngine.rankWave(
        [_wc('X', 'x'), _wc('Hit', 'hit', pop: 1.0)],
        profile: TasteProfile.empty,
        cooldown: const {},
        dislikedKeys: const {},
        weights: ScoreWeights.popular,
        constraints: WaveConstraints.balanced,
        recentArtists: const [],
        servedKeys: const {},
        nowSec: 0,
        limit: 10,
      );
      expect(out.first.artist, 'Hit');
    });
  });

  group('WaveEngine.looksLikeJunk (фильтр мусора)', () {
    Track tr(String artist, String title) => Track(
        id: '$artist::$title',
        title: title,
        artist: artist,
        source: SourceType.youtube);
    test('караоке — мусор', () {
      expect(
          WaveEngine.looksLikeJunk(
              tr('Sing Along', 'Bohemian Rhapsody (Karaoke Version)')),
          isTrue);
    });
    test('nightcore-канал — мусор',
        () => expect(WaveEngine.looksLikeJunk(tr('Nightcore World', 'Faded')),
            isTrue));
    test('8D Audio — мусор',
        () => expect(
            WaveEngine.looksLikeJunk(tr('X', 'Blinding Lights (8D Audio)')),
            isTrue));
    test('обычный трек — не мусор',
        () => expect(
            WaveEngine.looksLikeJunk(tr('The Weeknd', 'Blinding Lights')),
            isFalse));
  });
}
