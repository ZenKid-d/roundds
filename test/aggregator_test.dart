import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/data/aggregator.dart';
import 'package:roundds/domain/models/playable_stream.dart';
import 'package:roundds/domain/models/source_type.dart';
import 'package:roundds/domain/models/track.dart';
import 'package:roundds/domain/music_source.dart';

/// Управляемый источник для тестов агрегатора.
class FakeSource implements MusicSource {
  FakeSource(
    this.type, {
    this.results = const [],
    this.throwOnResolve = false,
    this.ready = true,
  });

  @override
  final SourceType type;

  List<Track> results;
  bool throwOnResolve;
  bool ready;
  int searchCalls = 0;
  int feedCalls = 0;

  @override
  Future<bool> get isReady async => ready;

  @override
  bool get supportsPaging => true;

  @override
  Future<List<Track>> search(String query, {int limit = 20, int page = 0}) async {
    searchCalls++;
    return results;
  }

  @override
  Future<List<Track>> feed({int limit = 20}) async {
    feedCalls++;
    return results;
  }

  @override
  Future<PlayableStream> resolveStream(Track track) async {
    if (throwOnResolve) throw Exception('resolve failed');
    return PlayableStream(uri: Uri.parse('https://example/${track.id}'));
  }

  @override
  Future<bool> downloadTo(Track track, String path,
          {void Function(int received, int total)? onProgress}) async =>
      false;
}

Track track(SourceType s, String id) =>
    Track(id: id, title: id, artist: 'artist-$id', source: s);

void main() {
  group('Aggregator.search / _interleave', () {
    test('переплетает источники round-robin', () async {
      final yt = FakeSource(SourceType.youtube,
          results: [track(SourceType.youtube, '1'), track(SourceType.youtube, '2')]);
      final sc = FakeSource(SourceType.soundcloud,
          results: [track(SourceType.soundcloud, '3')]);
      final agg = Aggregator(
        {SourceType.youtube: yt, SourceType.soundcloud: sc},
        enabled: {SourceType.youtube, SourceType.soundcloud},
      );

      final res = await agg.search('q');
      expect(res.map((t) => t.uid).toList(),
          ['youtube:1', 'soundcloud:3', 'youtube:2']);
    });

    test('дедуп по uid', () async {
      final dup = track(SourceType.youtube, '1');
      final yt = FakeSource(SourceType.youtube, results: [dup, dup]);
      final agg = Aggregator({SourceType.youtube: yt},
          enabled: {SourceType.youtube});

      final res = await agg.search('q');
      expect(res.length, 1);
    });

    test('падение одного источника не роняет поиск', () async {
      final yt = FakeSource(SourceType.youtube,
          results: [track(SourceType.youtube, '1')]);
      final sc = _ThrowingSearchSource(SourceType.soundcloud);
      final agg = Aggregator(
        {SourceType.youtube: yt, SourceType.soundcloud: sc},
        enabled: {SourceType.youtube, SourceType.soundcloud},
      );

      final res = await agg.search('q');
      expect(res.map((t) => t.uid).toList(), ['youtube:1']);
    });
  });

  group('Aggregator.resolveStreamWithFallback', () {
    test('падение родного источника → фолбэк на YouTube (та же песня)', () async {
      // YouTube-результат — ТА ЖЕ песня (артист+название), иначе подмену
      // отсекает проверка совпадения (не играем чужой трек).
      final yt = FakeSource(SourceType.youtube, results: [
        const Track(
            id: 'ytid',
            title: 'sc1',
            artist: 'artist-sc1',
            source: SourceType.youtube),
      ]);
      final sc = FakeSource(SourceType.soundcloud, throwOnResolve: true);
      final agg = Aggregator(
        {SourceType.youtube: yt, SourceType.soundcloud: sc},
        enabled: {SourceType.youtube, SourceType.soundcloud},
      );

      final stream =
          await agg.resolveStreamWithFallback(track(SourceType.soundcloud, 'sc1'));
      expect(stream.uri.toString(), contains('ytid'));
    });

    test('фолбэк не подставляет чужую песню → пробрасывает ошибку', () async {
      // YouTube нашёл лишь посторонний трек — совпадения нет, подмены быть не
      // должно, исходная ошибка родного источника пробрасывается.
      final yt = FakeSource(SourceType.youtube,
          results: [track(SourceType.youtube, 'ytid')]);
      final sc = FakeSource(SourceType.soundcloud, throwOnResolve: true);
      final agg = Aggregator(
        {SourceType.youtube: yt, SourceType.soundcloud: sc},
        enabled: {SourceType.youtube, SourceType.soundcloud},
      );

      await expectLater(
        agg.resolveStreamWithFallback(track(SourceType.soundcloud, 'sc1')),
        throwsA(isA<Exception>()),
      );
    });

    test('без включённого YouTube фолбэка нет — пробрасываем ошибку', () async {
      final yt = FakeSource(SourceType.youtube,
          results: [track(SourceType.youtube, 'ytid')]);
      final sc = FakeSource(SourceType.soundcloud, throwOnResolve: true);
      final agg = Aggregator(
        {SourceType.youtube: yt, SourceType.soundcloud: sc},
        enabled: {SourceType.soundcloud}, // YouTube выключен
      );

      await expectLater(
        agg.resolveStreamWithFallback(track(SourceType.soundcloud, 'sc1')),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Aggregator.youtubeMatch', () {
    test('находит ту же песню на YouTube для не-YT источника', () async {
      final yt = FakeSource(SourceType.youtube, results: [
        const Track(
            id: 'ytid',
            title: 'sc1',
            artist: 'artist-sc1',
            source: SourceType.youtube),
      ]);
      final sc = FakeSource(SourceType.soundcloud);
      final agg = Aggregator(
        {SourceType.youtube: yt, SourceType.soundcloud: sc},
        enabled: {SourceType.youtube, SourceType.soundcloud},
      );

      final m = await agg.youtubeMatch(track(SourceType.soundcloud, 'sc1'));
      expect(m?.uid, 'youtube:ytid');
    });

    test('на YouTube лишь чужой трек → null (не подставляем)', () async {
      final yt = FakeSource(SourceType.youtube,
          results: [track(SourceType.youtube, 'ytid')]);
      final sc = FakeSource(SourceType.soundcloud);
      final agg = Aggregator(
        {SourceType.youtube: yt, SourceType.soundcloud: sc},
        enabled: {SourceType.youtube, SourceType.soundcloud},
      );

      expect(await agg.youtubeMatch(track(SourceType.soundcloud, 'sc1')), isNull);
    });

    test('для YouTube-трека возвращает его же', () async {
      final yt = FakeSource(SourceType.youtube);
      final agg = Aggregator({SourceType.youtube: yt},
          enabled: {SourceType.youtube});
      final t = track(SourceType.youtube, 'x');
      expect((await agg.youtubeMatch(t))?.uid, t.uid);
    });

    test('YouTube выключен → null', () async {
      final yt = FakeSource(SourceType.youtube,
          results: [track(SourceType.youtube, 'ytid')]);
      final sc = FakeSource(SourceType.soundcloud);
      final agg = Aggregator(
        {SourceType.youtube: yt, SourceType.soundcloud: sc},
        enabled: {SourceType.soundcloud},
      );
      expect(await agg.youtubeMatch(track(SourceType.soundcloud, 'sc1')), isNull);
    });
  });

  group('Aggregator TTL-кэш', () {
    test('повторный поиск в пределах TTL не бьёт в источник', () async {
      final yt = FakeSource(SourceType.youtube,
          results: [track(SourceType.youtube, '1')]);
      final agg = Aggregator({SourceType.youtube: yt},
          enabled: {SourceType.youtube});

      await agg.search('q');
      await agg.search('q');
      expect(yt.searchCalls, 1);
    });

    test('пустой результат не кэшируется', () async {
      final yt = FakeSource(SourceType.youtube, results: const []);
      final agg = Aggregator({SourceType.youtube: yt},
          enabled: {SourceType.youtube});

      await agg.search('q');
      await agg.search('q');
      expect(yt.searchCalls, 2);
    });

    test('clearCache сбрасывает кэш ленты', () async {
      final yt = FakeSource(SourceType.youtube,
          results: [track(SourceType.youtube, '1')]);
      final agg = Aggregator({SourceType.youtube: yt},
          enabled: {SourceType.youtube});

      await agg.feed();
      await agg.feed();
      expect(yt.feedCalls, 1);

      agg.clearCache();
      await agg.feed();
      expect(yt.feedCalls, 2);
    });

    test('setEnabled инвалидирует кэш', () async {
      final yt = FakeSource(SourceType.youtube,
          results: [track(SourceType.youtube, '1')]);
      final agg = Aggregator({SourceType.youtube: yt},
          enabled: {SourceType.youtube});

      await agg.search('q');
      agg.setEnabled({SourceType.youtube});
      await agg.search('q');
      expect(yt.searchCalls, 2);
    });
  });

  group('Aggregator — дедуп одновременных запросов', () {
    test('два параллельных search() с тем же query бьют источник один раз',
        () async {
      final yt = _DelayedSource(SourceType.youtube,
          results: [track(SourceType.youtube, '1')]);
      final agg = Aggregator({SourceType.youtube: yt},
          enabled: {SourceType.youtube});

      final f1 = agg.search('q');
      final f2 = agg.search('q'); // стартует, пока f1 ещё не резолвился
      yt.complete();
      final r1 = await f1;
      final r2 = await f2;
      expect(yt.searchCalls, 1);
      expect(r1.map((t) => t.uid), r2.map((t) => t.uid));
    });

    test('разные query не дедупятся друг с другом', () async {
      final yt = _DelayedSource(SourceType.youtube,
          results: [track(SourceType.youtube, '1')]);
      final agg = Aggregator({SourceType.youtube: yt},
          enabled: {SourceType.youtube});

      final f1 = agg.search('a');
      final f2 = agg.search('b');
      yt.complete();
      await f1;
      await f2;
      expect(yt.searchCalls, 2);
    });

    test('после завершения in-flight запроса следующий вызов бьёт источник снова',
        () async {
      final yt = _DelayedSource(SourceType.youtube, results: const []);
      final agg = Aggregator({SourceType.youtube: yt},
          enabled: {SourceType.youtube});

      final f1 = agg.search('q');
      yt.complete();
      await f1;
      // Пустой результат не кэшируется — но и не должен залипнуть в in-flight.
      yt.reset();
      final f2 = agg.search('q');
      yt.complete();
      await f2;
      expect(yt.searchCalls, 2);
    });

    test('два параллельных feed() бьют источник один раз', () async {
      final yt = _DelayedSource(SourceType.youtube,
          results: [track(SourceType.youtube, '1')]);
      final agg = Aggregator({SourceType.youtube: yt},
          enabled: {SourceType.youtube});

      final f1 = agg.feed();
      final f2 = agg.feed();
      yt.complete();
      await f1;
      await f2;
      expect(yt.feedCalls, 1);
    });
  });
}

/// Источник, у которого падает поиск (проверяем устойчивость агрегатора).
class _ThrowingSearchSource extends FakeSource {
  _ThrowingSearchSource(super.type);

  @override
  Future<List<Track>> search(String query, {int limit = 20, int page = 0}) async {
    throw Exception('search failed');
  }
}

/// Источник, который зависает до вызова [complete] — нужен, чтобы гарантированно
/// поймать момент, когда второй параллельный запрос ещё застаёт первый «в полёте».
class _DelayedSource extends FakeSource {
  _DelayedSource(super.type, {super.results});

  Completer<void> _gate = Completer<void>();

  void complete() {
    if (!_gate.isCompleted) _gate.complete();
  }

  void reset() => _gate = Completer<void>();

  @override
  Future<List<Track>> search(String query, {int limit = 20, int page = 0}) async {
    await _gate.future;
    return super.search(query, limit: limit, page: page);
  }

  @override
  Future<List<Track>> feed({int limit = 20}) async {
    await _gate.future;
    return super.feed(limit: limit);
  }
}
