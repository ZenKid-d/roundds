import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/data/recs/wave_constraints.dart';

/// Тестовый кандидат: артист, ключ дедупа, сколько секунд назад звучал.
class _C {
  const _C(this.artist, this.key, {this.ago});
  final String artist;
  final String key;
  final int? ago;
}

List<_C> _arrange(
  List<_C> input, {
  WaveConstraints c = WaveConstraints.balanced,
  List<String> recent = const [],
  int limit = 50,
}) =>
    WaveSequencer.arrange<_C>(
      input,
      artistKeyOf: (x) => x.artist,
      dedupKeyOf: (x) => x.key,
      lastPlayedSecAgoOf: (x) => x.ago,
      constraints: c,
      recentArtists: recent,
      limit: limit,
    );

void main() {
  group('WaveSequencer anti-repetition', () {
    test('один артист не чаще, чем раз в 5 позиций', () {
      final input = <_C>[];
      for (final a in ['A', 'B', 'C', 'D', 'E']) {
        for (var i = 0; i < 12; i++) {
          input.add(_C(a, '$a$i'));
        }
      }
      final out = _arrange(input,
          c: const WaveConstraints(minArtistGap: 5, maxPerArtistSession: 100),
          limit: 20);
      final artists = [for (final x in out) x.artist];
      expect(artists.length, greaterThanOrEqualTo(15));
      for (var i = 0; i < artists.length; i++) {
        for (var j = i + 1; j < artists.length && j < i + 5; j++) {
          expect(artists[i] == artists[j], isFalse,
              reason: 'артист ${artists[i]} повторился в пределах 5 позиций');
        }
      }
    });

    test('не более 3 раз за сессию', () {
      final input = <_C>[for (var i = 0; i < 12; i++) _C('A', 'a$i')];
      for (var i = 0; i < 30; i++) {
        input.add(_C('B$i', 'b$i')); // разные артисты-разбавители
      }
      final out = _arrange(input,
          c: const WaveConstraints(minArtistGap: 5, maxPerArtistSession: 3),
          limit: 40);
      expect(out.where((x) => x.artist == 'A').length, lessThanOrEqualTo(3));
    });

    test('cooldown исключает недавно звучавшие треки', () {
      final input = [
        const _C('A', 'a', ago: 0), // только что
        const _C('A', 'a2', ago: 3 * 86400), // 3 дня — ещё в cooldown
        const _C('B', 'b', ago: 8 * 86400), // 8 дней — cooldown прошёл
        const _C('C', 'c'), // никогда не звучал
      ];
      final out = _arrange(input,
          c: const WaveConstraints(
              minArtistGap: 1, maxPerArtistSession: 100, cooldownDays: 7));
      final keys = {for (final x in out) x.key};
      expect(keys.contains('a'), isFalse);
      expect(keys.contains('a2'), isFalse);
      expect(keys.contains('b'), isTrue);
      expect(keys.contains('c'), isTrue);
    });

    test('кросс-источниковый дедуп: одинаковый ключ один раз', () {
      final input = [
        const _C('A', 'same'),
        const _C('A', 'same'), // дубль (напр. YTM + SC)
        const _C('B', 'other'),
      ];
      final out = _arrange(input,
          c: const WaveConstraints(minArtistGap: 1, maxPerArtistSession: 100));
      expect(out.where((x) => x.key == 'same').length, 1);
    });

    test('recentArtists учитывается в gap на стыке буфера', () {
      final input = [
        const _C('A', 'a1'),
        const _C('B', 'b1'),
        const _C('C', 'c1'),
        const _C('D', 'd1'),
        const _C('A', 'a2'),
      ];
      final out = _arrange(input,
          c: const WaveConstraints(minArtistGap: 5, maxPerArtistSession: 100),
          recent: ['A'],
          limit: 5);
      expect(out.first.artist == 'A', isFalse);
    });
  });
}
