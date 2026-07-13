import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/data/aggregator.dart';
import 'package:roundds/domain/models/source_type.dart';
import 'package:roundds/domain/models/track.dart';

/// [Aggregator.pickMatch] — выбор из выдачи поиска трека, действительно
/// совпадающего с искомым (для межисточникового фолбэка). Отсекает чужие треки/
/// каверы, не подсовывая под тем же названием посторонний результат.
Track _t(String artist, String title, {SourceType source = SourceType.youtube}) =>
    Track(id: '$artist:$title', title: title, artist: artist, source: source);

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
}
