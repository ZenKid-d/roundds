import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/data/recs/recs_signals.dart';

void main() {
  group('RecsSignals.classifyPlayback', () {
    test('<30 сек — жёсткий скип', () {
      expect(
        RecsSignals.classifyPlayback(playedMs: 15000, durationMs: 200000),
        SignalKind.skipHard,
      );
    });

    test('>30 сек, но <25% — жёсткий скип', () {
      // 10-мин трек, 40 сек = 6.7%
      expect(
        RecsSignals.classifyPlayback(playedMs: 40000, durationMs: 600000),
        SignalKind.skipHard,
      );
    });

    test('25–60% — мягкий скип', () {
      expect(
        RecsSignals.classifyPlayback(playedMs: 80000, durationMs: 200000), // 40%
        SignalKind.skipSoft,
      );
    });

    test('60–85% — нейтрально (play)', () {
      expect(
        RecsSignals.classifyPlayback(playedMs: 140000, durationMs: 200000), // 70%
        SignalKind.play,
      );
    });

    test('>85% — дослушал', () {
      expect(
        RecsSignals.classifyPlayback(playedMs: 190000, durationMs: 200000), // 95%
        SignalKind.complete,
      );
    });

    test('граница 25% — уже мягкий, не жёсткий', () {
      expect(
        RecsSignals.classifyPlayback(playedMs: 50000, durationMs: 200000), // 25%
        SignalKind.skipSoft,
      );
    });

    test('неизвестная длительность: >30 сек — нейтрально', () {
      expect(
        RecsSignals.classifyPlayback(playedMs: 45000, durationMs: 0),
        SignalKind.play,
      );
    });

    test('неизвестная длительность: <30 сек — жёсткий скип', () {
      expect(
        RecsSignals.classifyPlayback(playedMs: 20000, durationMs: 0),
        SignalKind.skipHard,
      );
    });
  });

  group('RecsWeights.of (веса из ТЗ)', () {
    test('значения', () {
      expect(RecsWeights.of(SignalKind.skipHard), -1.0);
      expect(RecsWeights.of(SignalKind.skipSoft), -0.3);
      expect(RecsWeights.of(SignalKind.complete), 0.5);
      expect(RecsWeights.of(SignalKind.like), 1.5);
      expect(RecsWeights.of(SignalKind.dislike), -2.0);
      expect(RecsWeights.of(SignalKind.repeat), 1.0);
      expect(RecsWeights.of(SignalKind.play), 0.0);
      expect(RecsWeights.of(SignalKind.start), 0.0);
    });
  });
}
