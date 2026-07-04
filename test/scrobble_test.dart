import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/playback/playback_controller.dart';

void main() {
  group('PlaybackController.shouldScrobble', () {
    test('трек короче 30 сек не скроббится', () {
      expect(
        PlaybackController.shouldScrobble(durationMs: 25000, playedMs: 25000),
        isFalse,
      );
    });

    test('прослушано меньше половины — нет', () {
      expect(
        PlaybackController.shouldScrobble(durationMs: 200000, playedMs: 90000),
        isFalse,
      );
    });

    test('прослушано больше половины — да', () {
      expect(
        PlaybackController.shouldScrobble(durationMs: 200000, playedMs: 120000),
        isTrue,
      );
    });

    test('длинный трек: порог ограничен 4 минутами (240 сек)', () {
      // dur=10 мин → половина 5 мин, но кап 4 мин.
      expect(
        PlaybackController.shouldScrobble(durationMs: 600000, playedMs: 245000),
        isTrue,
      );
      expect(
        PlaybackController.shouldScrobble(durationMs: 600000, playedMs: 235000),
        isFalse,
      );
    });

    test('неизвестная длительность: порог 60 сек', () {
      expect(
        PlaybackController.shouldScrobble(durationMs: 0, playedMs: 65000),
        isTrue,
      );
      expect(
        PlaybackController.shouldScrobble(durationMs: 0, playedMs: 40000),
        isFalse,
      );
    });

    test('соблюдается абсолютный минимум 20 сек', () {
      // dur=30001 (не отсекается), половина 15000 — но нужно ещё >= 20000.
      expect(
        PlaybackController.shouldScrobble(durationMs: 30001, playedMs: 16000),
        isFalse,
      );
      expect(
        PlaybackController.shouldScrobble(durationMs: 30001, playedMs: 21000),
        isTrue,
      );
    });
  });
}
