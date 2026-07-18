import 'dart:math';

import '../domain/models/track.dart';

/// Режим повтора очереди. Независимый enum (не привязан к audio_service),
/// чтобы логика навигации тестировалась без Android-зависимостей. Совпадает
/// по значениям с RoundsAudioHandler.LoopMode — конвертируется на границе.
enum RepeatMode { off, all, one }

/// Чистая логика выбора следующего индекса в очереди, выделенная из
/// RoundsAudioHandler. Раньше она дублировалась дословно в _nextIndex() и
/// _advance() (~30 строк × 2); теперь единая тестируемая функция.
///
/// Не зависит от just_audio / audio_service-рантайма — только от данных
/// очереди, что делает её покрытой unit-тестами (test/queue_navigation_test.dart).
///
/// Возвращает null, когда очередь пуста или достигнут конец без повтора.
int? nextIndex({
  required List<Track> queue,
  required int index,
  required bool shuffle,
  required RepeatMode repeat,
  required Random rng,
}) {
  if (queue.isEmpty) return null;
  if (repeat == RepeatMode.one) return index; // бесшовный повтор одного трека

  int next;
  if (shuffle && queue.length > 1) {
    // Умное перемешивание: избегаем того же артиста подряд, если можно.
    // До 6 попыток найти трек другого артиста; если не вышло (очередь из
    // одного артиста) — берём, что есть.
    // index может быть вне диапазона (например -1 до первой загрузки) —
    // тогда просто нет "текущего" артиста, которого нужно избегать.
    final curArtist = (index >= 0 && index < queue.length)
        ? queue[index].artist.toLowerCase()
        : null;
    next = index;
    for (var attempt = 0; attempt < 6; attempt++) {
      // nextInt(len-1) + (сдвиг, чтобы не выпал текущий): даёт равномерное
      // распределение по всем индексам кроме текущего.
      var n = rng.nextInt(queue.length - 1);
      if (n >= index) n += 1;
      next = n;
      if (curArtist == null || queue[n].artist.toLowerCase() != curArtist) {
        break;
      }
    }
  } else {
    next = index + 1;
  }

  if (next >= queue.length) {
    if (repeat == RepeatMode.all) {
      next = 0;
    } else {
      return null; // конец очереди
    }
  }
  return next;
}

/// Конвертация LoopMode из audio_handler в RepeatMode. На границе слоёв:
/// audio_handler держит свой enum (исторически сложилось), чистая логика
/// работает с RepeatMode.
RepeatMode toRepeatMode(int index) {
  // LoopMode.values = [off, all, one] — индексы совпадают.
  return RepeatMode.values[index.clamp(0, 2)];
}

