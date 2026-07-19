import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roundds/core/downloads_controller.dart';
import 'package:roundds/data/aggregator.dart';
import 'package:roundds/domain/models/source_type.dart';
import 'package:roundds/domain/models/track.dart';

Track _t(String id, String artist, String title, SourceType source) => Track(
      id: id,
      title: title,
      artist: artist,
      source: source,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('roundds_downloads_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<DownloadsController> controllerWithPersisted(
      List<({Track track, String path})> entries) async {
    SharedPreferences.setMockInitialValues({
      'downloads': jsonEncode([
        for (final e in entries) {'track': e.track.toJson(), 'path': e.path},
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    return DownloadsController(prefs, Dio(), Aggregator(const {}));
  }

  group('DownloadsController.localMatchByNormKey — офлайн-дубль для фолбэка', () {
    test('находит трек с другого источника по artist+title', () async {
      final path = '${tmp.path}/song.audio';
      File(path).writeAsStringSync('audio-bytes');
      final track = _t('yt1', 'Artist Name', 'Song Title', SourceType.youtube);
      final dl = await controllerWithPersisted([(track: track, path: path)]);

      final match = dl.localMatchByNormKey('Artist Name', 'Song Title');
      expect(match, isNotNull);
      expect(match!.track.uid, track.uid);
      expect(match.path, path);
    });

    test('нормализация: регистр/пунктуация не мешают совпадению', () async {
      final path = '${tmp.path}/song.audio';
      File(path).writeAsStringSync('audio-bytes');
      final track =
          _t('sc1', 'ARTIST name', 'Song, Title!', SourceType.soundcloud);
      final dl = await controllerWithPersisted([(track: track, path: path)]);

      expect(dl.localMatchByNormKey('artist name', 'song title'), isNotNull);
    });

    test('нет совпадения по artist+title → null', () async {
      final path = '${tmp.path}/song.audio';
      File(path).writeAsStringSync('audio-bytes');
      final track = _t('yt1', 'Artist', 'Song', SourceType.youtube);
      final dl = await controllerWithPersisted([(track: track, path: path)]);

      expect(dl.localMatchByNormKey('Other Artist', 'Other Song'), isNull);
    });

    test('файл пропал с диска → null (не отдаём битую ссылку)', () async {
      final path = '${tmp.path}/gone.audio'; // не создаём файл
      final track = _t('yt1', 'Artist', 'Song', SourceType.youtube);
      final dl = await controllerWithPersisted([(track: track, path: path)]);

      expect(dl.localMatchByNormKey('Artist', 'Song'), isNull);
    });

    test('нет скачанных треков вовсе → null', () async {
      final dl = await controllerWithPersisted(const []);
      expect(dl.localMatchByNormKey('Artist', 'Song'), isNull);
    });

    test('remove() убирает трек из индекса normKey', () async {
      final path = '${tmp.path}/song.audio';
      File(path).writeAsStringSync('audio-bytes');
      final track = _t('yt1', 'Artist', 'Song', SourceType.youtube);
      final dl = await controllerWithPersisted([(track: track, path: path)]);
      expect(dl.localMatchByNormKey('Artist', 'Song'), isNotNull);

      await dl.remove(track.uid);
      expect(dl.localMatchByNormKey('Artist', 'Song'), isNull);
    });
  });
}
