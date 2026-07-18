import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/domain/models/source_type.dart';
import 'package:roundds/domain/models/track.dart';

/// Тесты сериализации Track: round-trip, дефолты и валидация повреждённого
/// JSON. Раньше fromJson бросал TypeError на отсутствии id — теперь понятная
/// FormatException, и бэкап-импорт может пропустить битую запись, не роняя
/// весь импорт.
void main() {
  group('Track.toJson / fromJson round-trip', () {
    test('полный трек переживает сериализацию без потерь', () {
      const src = Track(
        id: 'abc123',
        title: 'Песня',
        artist: 'Артист',
        album: 'Альбом',
        artworkUrl: 'https://example.com/a.jpg',
        duration: Duration(milliseconds: 184_000),
        source: SourceType.youtube,
        extra: {'k': 'v', 'n': 42},
      );
      final out = Track.fromJson(src.toJson());
      expect(out.id, src.id);
      expect(out.title, src.title);
      expect(out.artist, src.artist);
      expect(out.album, src.album);
      expect(out.artworkUrl, src.artworkUrl);
      expect(out.duration, src.duration);
      expect(out.source, src.source);
      expect(out.extra, src.extra);
      expect(out.uid, src.uid);
    });

    test('дефолты: отсутствуют title/artist/source → пустые строки/youtube', () {
      final t = Track.fromJson({'id': 'x', 'extra': {}});
      expect(t.title, '');
      expect(t.artist, '');
      expect(t.source, SourceType.youtube);
      expect(t.duration, isNull);
      expect(t.album, isNull);
      expect(t.artworkUrl, isNull);
      expect(t.extra, isEmpty);
    });

    test('durationMs приходит как double (не падает на as int)', () {
      // JSON-источники иногда отдают число с плавающей точкой; раньше
      // `j['durationMs'] as int` ронял парсинг. Теперь берём через num.
      final t = Track.fromJson({'id': 'x', 'durationMs': 184000.0});
      expect(t.duration, const Duration(milliseconds: 184_000));
    });

    test('durationMs как int работает как прежде', () {
      final t = Track.fromJson({'id': 'x', 'durationMs': 60_000});
      expect(t.duration, const Duration(seconds: 60));
    });
  });

  group('Track.fromJson валидация', () {
    test('отсутствует id → FormatException (не TypeError)', () {
      expect(
        () => Track.fromJson({'title': 'без id'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('id пустая строка → FormatException', () {
      expect(
        () => Track.fromJson({'id': ''}),
        throwsA(isA<FormatException>()),
      );
    });

    test('id не строка (число) → FormatException', () {
      expect(
        () => Track.fromJson({'id': 12345}),
        throwsA(isA<FormatException>()),
      );
    });

    test('unknown source id → fallback на youtube (через SourceTypeX.fromId)',
        () {
      final t = Track.fromJson({'id': 'x', 'source': 'неизвестный'});
      expect(t.source, SourceType.youtube);
    });
  });

  group('Track uid и equality', () {
    test('uid = source.id:id', () {
      const t = Track(id: 'v1', title: '', artist: '', source: SourceType.vk);
      expect(t.uid, 'vk:v1');
    });

    test('равенство по uid, а не по содержимому', () {
      const a = Track(id: '1', title: 'A', artist: 'X', source: SourceType.youtube);
      const b = Track(id: '1', title: 'B', artist: 'Y', source: SourceType.youtube);
      expect(a == b, isTrue); // одинаковый uid
      expect(a.hashCode, b.hashCode);
    });

    test('разные источники с одинаковым id → разные треки', () {
      const yt =
          Track(id: '1', title: '', artist: '', source: SourceType.youtube);
      const sc = Track(
          id: '1', title: '', artist: '', source: SourceType.soundcloud);
      expect(yt == sc, isFalse);
    });
  });
}
