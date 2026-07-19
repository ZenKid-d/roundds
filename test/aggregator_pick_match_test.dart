import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/data/aggregator.dart';
import 'package:roundds/domain/models/source_type.dart';
import 'package:roundds/domain/models/track.dart';

/// [Aggregator.pickMatch] — выбор из выдачи поиска трека, действительно
/// совпадающего с искомым (для межисточникового фолбэка). Отсекает чужие треки/
/// каверы, не подсовывая под тем же названием посторонний результат.
Track _t(
  String artist,
  String title, {
  SourceType source = SourceType.youtube,
  Duration? duration,
}) =>
    Track(
      id: '$artist:$title:${source.id}',
      title: title,
      artist: artist,
      source: source,
      duration: duration,
    );

void main() {
  group('Aggregator.pickMatch', () {
    test('находит точное совпадение артист+название', () {
      final want = _t('Daft Punk', 'One More Time', source: SourceType.yandex);
      final got = Aggregator.pickMatch(want, [
        _t('Someone Else', 'Random'),
        _t('Daft Punk', 'One More Time'),
      ]);
      expect(got, isNotNull);
      expect(got!.title, 'One More Time');
      expect(got.source, SourceType.youtube);
    });

    test('нет совпадающего трека → null (чужой не подставляем)', () {
      final want = _t('Daft Punk', 'One More Time', source: SourceType.yandex);
      final got = Aggregator.pickMatch(want, [
        _t('Cover Band', 'Totally Different Song'),
        _t('Another Artist', 'Some Other Track'),
      ]);
      expect(got, isNull);
    });

    test('пустая выдача → null', () {
      final want = _t('X', 'Y');
      expect(Aggregator.pickMatch(want, const []), isNull);
    });
  });

  group('Aggregator.bestMatch (скоринг с учётом длительности)', () {
    test('из дублей выбирает версию той же длительности, не радио-эдит', () {
      // Полная версия (5:00) против радио-эдита (3:00) того же трека — полная
      // должна набрать выше по сигналу длительности.
      final want = _t('Daft Punk', 'Get Lucky',
          source: SourceType.yandex, duration: const Duration(minutes: 6, seconds: 9));
      final got = Aggregator.bestMatch(want, [
        _t('Daft Punk', 'Get Lucky', duration: const Duration(minutes: 4, seconds: 0)),
        _t('Daft Punk', 'Get Lucky', duration: const Duration(minutes: 6, seconds: 9)),
      ]);
      expect(got, isNotNull);
      expect(got!.match.duration, const Duration(minutes: 6, seconds: 9));
    });

    test('из 3 кандидатов с разной длительностью — ближайший по длине', () {
      // Искомый 4:21; кандидаты 4:22 (Δ=1с), 4:30 (Δ=9с), 3:50 (Δ=31с).
      // Ближайший по длительности должен победить — у всех название/артист точные,
      // так что решает сигнал длительности.
      final want = _t('Radiohead', 'Karma Police',
          source: SourceType.yandex, duration: const Duration(minutes: 4, seconds: 21));
      final got = Aggregator.bestMatch(want, [
        _t('Radiohead', 'Karma Police', duration: const Duration(minutes: 3, seconds: 50)),
        _t('Radiohead', 'Karma Police', duration: const Duration(minutes: 4, seconds: 30)),
        _t('Radiohead', 'Karma Police', duration: const Duration(minutes: 4, seconds: 22)),
      ]);
      expect(got, isNotNull);
      expect(got!.match.duration, const Duration(minutes: 4, seconds: 22));
    });

    test('кавер той же длительности не проходит (гейт по артисту)', () {
      final want = _t('Bon Iver', 'Skinny Love',
          source: SourceType.yandex, duration: const Duration(minutes: 3, seconds: 55));
      final got = Aggregator.bestMatch(want, [
        _t('Birdy', 'Skinny Love', duration: const Duration(minutes: 3, seconds: 55)),
      ]);
      expect(got, isNull);
    });

    test('возвращает счёт победителя', () {
      final want = _t('The Weeknd', 'Blinding Lights',
          source: SourceType.yandex, duration: const Duration(minutes: 3, seconds: 20));
      final got = Aggregator.bestMatch(want, [
        _t('The Weeknd', 'Blinding Lights', duration: const Duration(minutes: 3, seconds: 20)),
      ]);
      expect(got, isNotNull);
      expect(got!.score, greaterThan(0.9));
    });

    test('пустая выдача → null', () {
      final want = _t('X', 'Y');
      expect(Aggregator.bestMatch(want, const []), isNull);
    });
  });
}
