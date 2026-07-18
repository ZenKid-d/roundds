import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roundds/core/library_controller.dart';
import 'package:roundds/domain/models/source_type.dart';
import 'package:roundds/domain/models/track.dart';

Track _t(String id, String artist, {String title = 'T'}) => Track(
      id: id,
      title: title,
      artist: artist,
      source: SourceType.youtube,
    );

Future<LibraryController> _controller([Map<String, Object>? initial]) async {
  SharedPreferences.setMockInitialValues(initial ?? {});
  final prefs = await SharedPreferences.getInstance();
  return LibraryController(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryController — безопасные операции с несуществующим id', () {
    test('renamePlaylist на удалённый id — no-op, не бросает', () async {
      final lib = await _controller();
      await expectLater(lib.renamePlaylist('missing', 'X'), completes);
    });

    test('addToPlaylist на удалённый id — no-op, не бросает', () async {
      final lib = await _controller();
      await expectLater(
        lib.addToPlaylist('missing', _t('1', 'A')),
        completes,
      );
    });

    test('removeFromPlaylist на удалённый id — no-op, не бросает', () async {
      final lib = await _controller();
      await expectLater(
        lib.removeFromPlaylist('missing', _t('1', 'A')),
        completes,
      );
    });

    test('removeDuplicates на удалённый id — возвращает 0', () async {
      final lib = await _controller();
      expect(await lib.removeDuplicates('missing'), 0);
    });
  });

  group('LibraryController.removeDuplicates', () {
    test('убирает дубликаты по uid', () async {
      final lib = await _controller();
      final pl = await lib.createPlaylist('P');
      final track = _t('1', 'A');
      await lib.addToPlaylist(pl.id, track);
      // addToPlaylist сам не дублирует по uid — добавим второй раз тем же
      // объектом напрямую в список, минуя защиту, чтобы проверить чистку.
      pl.tracks.add(track);
      final removed = await lib.removeDuplicates(pl.id);
      expect(removed, 1);
      expect(pl.tracks.length, 1);
    });

    test('убирает дубликаты по «артист — название» даже с разным uid', () async {
      final lib = await _controller();
      final pl = await lib.createPlaylist('P');
      pl.tracks.add(_t('1', 'Artist', title: 'Song'));
      pl.tracks.add(_t('2', 'Artist', title: 'Song')); // другой id, тот же трек
      final removed = await lib.removeDuplicates(pl.id);
      expect(removed, 1);
      expect(pl.tracks.length, 1);
    });

    test('без дубликатов — возвращает 0', () async {
      final lib = await _controller();
      final pl = await lib.createPlaylist('P');
      await lib.addToPlaylist(pl.id, _t('1', 'A'));
      await lib.addToPlaylist(pl.id, _t('2', 'B'));
      expect(await lib.removeDuplicates(pl.id), 0);
      expect(pl.tracks.length, 2);
    });
  });

  group('LibraryController.topTracks — инвалидация кэша', () {
    test('новый pushHistory сбрасывает кэш топов', () async {
      final lib = await _controller();
      await lib.pushHistory(_t('1', 'A'));
      await lib.pushHistory(_t('1', 'A'));
      expect(lib.topTracks().first.value, 2);

      await lib.pushHistory(_t('1', 'A'));
      // Без инвалидации кэша здесь осталось бы значение 2.
      expect(lib.topTracks().first.value, 3);
    });

    test('importData со статистикой тоже сбрасывает кэш', () async {
      final lib = await _controller();
      await lib.pushHistory(_t('1', 'A'));
      expect(lib.topTracks().first.value, 1);

      await lib.importData({
        'stats': [
          {'track': _t('1', 'A').toJson(), 'count': 5},
        ],
      });
      expect(lib.topTracks().first.value, 6); // 1 + 5, счётчики суммируются
    });
  });

  group('LibraryController.importData — слияние и устойчивость к мусору', () {
    test('пропускает битые записи, не роняя весь импорт', () async {
      final lib = await _controller();
      await lib.importData({
        'liked': [
          _t('1', 'A').toJson(),
          {'title': 'no id'}, // битая запись — без id
          _t('2', 'B').toJson(),
        ],
      });
      expect(lib.liked.length, 2);
      expect(lib.liked.map((t) => t.id), containsAll(['1', '2']));
    });

    test('не дублирует уже существующие лайки/плейлисты по id', () async {
      final lib = await _controller();
      await lib.toggleLike(_t('1', 'A'));
      await lib.importData({
        'liked': [_t('1', 'A').toJson(), _t('2', 'B').toJson()],
      });
      expect(lib.liked.length, 2);
    });

    test('суммирует счётчики стата при повторном импорте', () async {
      final lib = await _controller();
      await lib.importData({
        'stats': [
          {'track': _t('1', 'A').toJson(), 'count': 3},
        ],
      });
      await lib.importData({
        'stats': [
          {'track': _t('1', 'A').toJson(), 'count': 2},
        ],
      });
      expect(lib.topTracks().first.value, 5);
    });
  });
}
