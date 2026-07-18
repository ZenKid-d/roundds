import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/domain/models/source_type.dart';
import 'package:roundds/domain/models/track.dart';
import 'package:roundds/playback/queue_navigation.dart';

Track _t(String id, String artist) => Track(
      id: id,
      title: id,
      artist: artist,
      source: SourceType.youtube,
    );

void main() {
  group('nextIndex — базовые случаи', () {
    test('пустая очередь — null', () {
      expect(
        nextIndex(
          queue: const [],
          index: 0,
          shuffle: false,
          repeat: RepeatMode.off,
          rng: Random(1),
        ),
        isNull,
      );
    });

    test('один трек, repeat off — конец очереди (null)', () {
      final queue = [_t('1', 'A')];
      expect(
        nextIndex(
          queue: queue,
          index: 0,
          shuffle: false,
          repeat: RepeatMode.off,
          rng: Random(1),
        ),
        isNull,
      );
    });

    test('один трек, repeat one — тот же индекс', () {
      final queue = [_t('1', 'A')];
      expect(
        nextIndex(
          queue: queue,
          index: 0,
          shuffle: false,
          repeat: RepeatMode.one,
          rng: Random(1),
        ),
        0,
      );
    });

    test('repeat one — тот же индекс даже с несколькими треками и shuffle', () {
      final queue = [_t('1', 'A'), _t('2', 'B'), _t('3', 'C')];
      expect(
        nextIndex(
          queue: queue,
          index: 1,
          shuffle: true,
          repeat: RepeatMode.one,
          rng: Random(1),
        ),
        1,
      );
    });

    test('без shuffle — просто следующий индекс', () {
      final queue = [_t('1', 'A'), _t('2', 'B'), _t('3', 'C')];
      expect(
        nextIndex(
          queue: queue,
          index: 0,
          shuffle: false,
          repeat: RepeatMode.off,
          rng: Random(1),
        ),
        1,
      );
    });

    test('конец очереди без повтора — null', () {
      final queue = [_t('1', 'A'), _t('2', 'B')];
      expect(
        nextIndex(
          queue: queue,
          index: 1,
          shuffle: false,
          repeat: RepeatMode.off,
          rng: Random(1),
        ),
        isNull,
      );
    });

    test('конец очереди с repeat all — индекс 0', () {
      final queue = [_t('1', 'A'), _t('2', 'B')];
      expect(
        nextIndex(
          queue: queue,
          index: 1,
          shuffle: false,
          repeat: RepeatMode.all,
          rng: Random(1),
        ),
        0,
      );
    });

    test('индекс -1 (до первой загрузки), без shuffle — 0', () {
      final queue = [_t('1', 'A'), _t('2', 'B')];
      expect(
        nextIndex(
          queue: queue,
          index: -1,
          shuffle: false,
          repeat: RepeatMode.off,
          rng: Random(1),
        ),
        0,
      );
    });
  });

  group('nextIndex — shuffle', () {
    test('никогда не возвращает текущий индекс', () {
      final queue = List.generate(5, (i) => _t('$i', 'Artist$i'));
      for (var seed = 0; seed < 50; seed++) {
        final rng = Random(seed);
        for (var idx = 0; idx < queue.length; idx++) {
          final result = nextIndex(
            queue: queue,
            index: idx,
            shuffle: true,
            repeat: RepeatMode.off,
            rng: rng,
          );
          expect(result, isNot(idx));
        }
      }
    });

    test('избегает того же артиста, если есть альтернатива', () {
      final queue = [
        _t('1', 'Same'),
        _t('2', 'Same'),
        _t('3', 'Other'),
      ];
      // curArtist в index=0 — 'Same'. Единственный трек другого артиста — index 2.
      // При достаточном числе попыток (6) должен быть найден 'Other'.
      final results = <int?>{};
      for (var seed = 0; seed < 30; seed++) {
        results.add(
          nextIndex(
            queue: queue,
            index: 0,
            shuffle: true,
            repeat: RepeatMode.off,
            rng: Random(seed),
          ),
        );
      }
      expect(results.contains(2), isTrue);
    });

    test('очередь из одного артиста — не падает, просто берёт что есть', () {
      final queue = [_t('1', 'Same'), _t('2', 'Same'), _t('3', 'Same')];
      for (var seed = 0; seed < 10; seed++) {
        final result = nextIndex(
          queue: queue,
          index: 0,
          shuffle: true,
          repeat: RepeatMode.off,
          rng: Random(seed),
        );
        expect(result, isNotNull);
        expect(result, isNot(0));
      }
    });

    test('shuffle с индексом -1 не падает (нет текущего артиста)', () {
      final queue = [_t('1', 'A'), _t('2', 'B'), _t('3', 'C')];
      for (var seed = 0; seed < 10; seed++) {
        expect(
          () => nextIndex(
            queue: queue,
            index: -1,
            shuffle: true,
            repeat: RepeatMode.off,
            rng: Random(seed),
          ),
          returnsNormally,
        );
      }
    });
  });

  group('toRepeatMode', () {
    test('конвертирует индексы LoopMode (off, all, one)', () {
      expect(toRepeatMode(0), RepeatMode.off);
      expect(toRepeatMode(1), RepeatMode.all);
      expect(toRepeatMode(2), RepeatMode.one);
    });
  });
}
