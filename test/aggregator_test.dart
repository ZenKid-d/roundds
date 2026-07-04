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
  Future<List<Track>> search(String query, {int limit = 20}) async {
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
    test('падение родного источника → фолбэк на YouTube', () async {
      final yt = FakeSource(SourceType.youtube,
          results: [track(SourceType.youtube, 'ytid')]);
      final sc = FakeSource(SourceType.soundcloud, throwOnResolve: true);
      final agg = Aggregator(
        {SourceType.youtube: yt, SourceType.soundcloud: sc},
        enabled: {SourceType.youtube, SourceType.soundcloud},
      );

      final stream =
          await agg.resolveStreamWithFallback(track(SourceType.soundcloud, 'sc1'));
      expect(stream.uri.toString(), contains('ytid'));
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
}

/// Источник, у которого падает поиск (проверяем устойчивость агрегатора).
class _ThrowingSearchSource extends FakeSource {
  _ThrowingSearchSource(super.type);

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    throw Exception('search failed');
  }
}
