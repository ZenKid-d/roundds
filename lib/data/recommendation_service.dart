import 'aggregator.dart';
import 'sources/soundcloud_source.dart';
import 'sources/yandex_source.dart';
import 'sources/youtube_music_source.dart';
import '../domain/models/source_type.dart';
import '../domain/models/track.dart';

/// Ряд рекомендаций для главного экрана.
class RecoRow {
  final String title;
  final List<Track> tracks;
  const RecoRow(this.title, this.tracks);
}

/// Клиентская система рекомендаций: «похожие» из эндпоинтов сервисов
/// (YouTube-радио / Яндекс / SoundCloud) + подбор по артисту, на основе
/// истории/лайков/статистики.
class RecommendationService {
  RecommendationService(this._yt, this._sc, this._ya, this._aggregator);

  final YoutubeMusicSource _yt;
  final SoundcloudSource _sc;
  final YandexSource _ya;
  final Aggregator _aggregator;

  /// Похожие на конкретный трек: сначала «родной» эндпоинт сервиса
  /// (для YouTube — радио-очередь InnerTube), иначе — подбор по артисту.
  Future<List<Track>> similarTo(Track seed) async {
    try {
      switch (seed.source) {
        case SourceType.youtube:
          final r = await _yt.relatedTo(seed.id);
          if (r.isNotEmpty) return r;
        case SourceType.yandex:
          final r = await _ya.similar(seed.id);
          if (r.isNotEmpty) return r;
        case SourceType.soundcloud:
          final r = await _sc.related(seed.id);
          if (r.isNotEmpty) return r;
        case SourceType.vk:
          // У VK нет нативного «похожего» эндпоинта — уходим в подбор по артисту.
          break;
      }
    } catch (_) {/* фолбэк ниже */}
    try {
      return await _aggregator.search(seed.artist, perSource: 12);
    } catch (_) {
      return const [];
    }
  }

  /// Взаимно перемешивает списки (round-robin) — чередование сидов/артистов
  /// для разнообразия ряда.
  List<Track> _interleave(List<List<Track>> lists,
      {Set<String>? exclude, int? maxPerArtist, int limit = 30}) {
    final out = <Track>[];
    final seen = <String>{...?exclude};
    final perArtist = <String, int>{};
    var i = 0;
    var active = true;
    while (active && out.length < limit) {
      active = false;
      for (final l in lists) {
        if (i < l.length) {
          active = true;
          final t = l[i];
          final aKey = t.artist.toLowerCase();
          if (seen.add(t.uid) &&
              (maxPerArtist == null ||
                  (perArtist[aKey] ?? 0) < maxPerArtist)) {
            out.add(t);
            perArtist[aKey] = (perArtist[aKey] ?? 0) + 1;
            if (out.length >= limit) break;
          }
        }
      }
      i++;
    }
    return out;
  }

  /// Персональные ряды для главной.
  Future<List<RecoRow>> forYou({
    required List<Track> history,
    required List<Track> liked,
    required List<MapEntry<Track, int>> topTracks,
    required List<MapEntry<String, int>> topArtists,
  }) async {
    final rows = <RecoRow>[];
    final known = <String>{
      ...history.map((t) => t.uid),
      ...liked.map((t) => t.uid),
    };
    final knownArtists = <String>{
      ...topArtists.map((e) => e.key.toLowerCase()),
      ...liked.map((t) => t.artist.toLowerCase()),
    };

    // Набор сидов: топ-треки + лайки + свежая история (без повторов).
    final seedMap = <String, Track>{};
    for (final s in [
      ...topTracks.take(3).map((e) => e.key),
      ...liked.take(3),
      ...history.take(2),
    ]) {
      seedMap.putIfAbsent(s.uid, () => s);
    }
    final seeds = seedMap.values.take(5).toList();

    // Похожие по каждому сиду — параллельно.
    final pools = seeds.isEmpty
        ? <List<Track>>[]
        : await Future.wait(seeds.map(similarTo));

    // 1) «Микс дня» — чередуем пулы, максимум 2 трека на артиста.
    final mix =
        _interleave(pools, exclude: known, maxPerArtist: 2, limit: 30);
    if (mix.length >= 6) {
      rows.add(RecoRow('Микс дня — по вашим вкусам', mix));
    }

    // 2) «Похожее на последний прослушанный».
    if (history.isNotEmpty) {
      final s = history.first;
      final sim =
          (await similarTo(s)).where((t) => !known.contains(t.uid)).toList();
      if (sim.isNotEmpty) {
        rows.add(RecoRow('Похожее на «${s.title}»', sim.take(24).toList()));
      }
    }

    // 3) «Ещё от {артист}» — для двух главных артистов.
    for (final a in topArtists.take(2)) {
      try {
        final more = (await _aggregator.search(a.key, perSource: 12))
            .where((t) => !known.contains(t.uid))
            .toList();
        if (more.isNotEmpty) {
          rows.add(RecoRow('Ещё от ${a.key}', more.take(24).toList()));
        }
      } catch (_) {}
    }

    // 3.5) «Потому что вы слушали…» — по самому прослушиваемому треку.
    if (topTracks.isNotEmpty) {
      final s = topTracks.first.key;
      if (history.isEmpty || s.uid != history.first.uid) {
        final sim =
            (await similarTo(s)).where((t) => !known.contains(t.uid)).toList();
        if (sim.isNotEmpty) {
          rows.add(RecoRow(
              'Потому что вы слушали «${s.title}»', sim.take(24).toList()));
        }
      }
    }

    // 4) «Открывайте новое» — из пулов, но артисты, которых ещё нет в
    // библиотеке (настоящее открытие, а не «ещё того же»).
    final discover = <String, Track>{};
    for (final p in pools) {
      for (final t in p) {
        if (!known.contains(t.uid) &&
            !knownArtists.contains(t.artist.toLowerCase())) {
          discover[t.uid] = t;
        }
      }
    }
    if (discover.length >= 6) {
      rows.add(RecoRow('Открывайте новое', discover.values.take(24).toList()));
    }

    return rows;
  }

  /// Стартовая очередь радио по треку (дальше плеер докручивает похожими).
  Future<List<Track>> radioFrom(Track seed) async {
    final sim = await similarTo(seed);
    final out = <Track>[seed];
    final have = {seed.uid};
    for (final t in sim) {
      if (have.add(t.uid)) out.add(t);
    }
    return out;
  }
}
