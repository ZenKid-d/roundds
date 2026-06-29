import '../domain/models/playable_stream.dart';
import '../domain/models/source_type.dart';
import '../domain/models/track.dart';
import '../domain/music_source.dart';

/// Сводит включённые источники в единый поиск/ленту и маршрутизирует
/// резолв потока к нужному источнику.
class Aggregator {
  Aggregator(this._sources, {Set<SourceType>? enabled})
      : _enabled = enabled ?? SourceType.values.toSet();

  final Map<SourceType, MusicSource> _sources;
  Set<SourceType> _enabled;

  Set<SourceType> get enabled => _enabled;
  void setEnabled(Set<SourceType> e) => _enabled = e;

  Iterable<MusicSource> get _active =>
      _sources.entries.where((e) => _enabled.contains(e.key)).map((e) => e.value);

  MusicSource sourceFor(SourceType t) => _sources[t]!;

  Future<bool> isReady(SourceType t) =>
      _enabled.contains(t) ? _sources[t]!.isReady : Future.value(false);

  /// Поиск по всем включённым источникам, результаты «переплетаются»
  /// (round-robin), чтобы лента не была занята одним сервисом.
  Future<List<Track>> search(String query, {int perSource = 15}) async {
    final futures = _active.map((s) async {
      try {
        return await s.search(query, limit: perSource);
      } catch (_) {
        return <Track>[];
      }
    });
    final lists = await Future.wait(futures);
    return _interleave(lists);
  }

  Future<List<Track>> feed({int perSource = 12}) async {
    final futures = _active.map((s) async {
      try {
        return await s.feed(limit: perSource);
      } catch (_) {
        return <Track>[];
      }
    });
    final lists = await Future.wait(futures);
    return _interleave(lists);
  }

  Future<PlayableStream> resolveStream(Track track) =>
      _sources[track.source]!.resolveStream(track);

  List<Track> _interleave(List<List<Track>> lists) {
    final out = <Track>[];
    final seen = <String>{};
    var i = 0;
    var added = true;
    while (added) {
      added = false;
      for (final list in lists) {
        if (i < list.length) {
          added = true;
          final t = list[i];
          if (seen.add(t.uid)) out.add(t);
        }
      }
      i++;
    }
    return out;
  }
}
