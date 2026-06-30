import 'aggregator.dart';
import 'sources/soundcloud_source.dart';
import 'sources/yandex_source.dart';
import '../domain/models/source_type.dart';
import '../domain/models/track.dart';

/// Ряд рекомендаций для главного экрана.
class RecoRow {
  final String title;
  final List<Track> tracks;
  const RecoRow(this.title, this.tracks);
}

/// Клиентская система рекомендаций: «похожие» из эндпоинтов сервисов
/// (Яндекс/SoundCloud) + подбор по артисту, на основе истории/лайков/статистики.
class RecommendationService {
  RecommendationService(this._sc, this._ya, this._aggregator);

  final SoundcloudSource _sc;
  final YandexSource _ya;
  final Aggregator _aggregator;

  /// Похожие на конкретный трек: сначала «родной» эндпоинт сервиса,
  /// иначе — подбор по артисту через общий поиск.
  Future<List<Track>> similarTo(Track seed) async {
    try {
      switch (seed.source) {
        case SourceType.yandex:
          final r = await _ya.similar(seed.id);
          if (r.isNotEmpty) return r;
        case SourceType.soundcloud:
          final r = await _sc.related(seed.id);
          if (r.isNotEmpty) return r;
        case SourceType.youtube:
          break; // у YouTube — фолбэк по артисту
      }
    } catch (_) {/* фолбэк ниже */}
    try {
      return await _aggregator.search(seed.artist, perSource: 12);
    } catch (_) {
      return const [];
    }
  }

  /// Персональные ряды для главной.
  Future<List<RecoRow>> forYou({
    required List<Track> history,
    required List<Track> liked,
    required List<MapEntry<Track, int>> topTracks,
    required List<MapEntry<String, int>> topArtists,
  }) async {
    final rows = <RecoRow>[];
    final seen = <String>{
      ...history.map((t) => t.uid),
      ...liked.map((t) => t.uid),
    };

    // «Похожее на последний прослушанный».
    if (history.isNotEmpty) {
      final s = history.first;
      final sim =
          (await similarTo(s)).where((t) => !seen.contains(t.uid)).toList();
      if (sim.isNotEmpty) {
        rows.add(RecoRow('Похожее на «${s.title}»', sim));
        seen.addAll(sim.map((t) => t.uid));
      }
    }

    // «Ещё от любимого артиста».
    if (topArtists.isNotEmpty) {
      final a = topArtists.first.key;
      try {
        final more = (await _aggregator.search(a, perSource: 12))
            .where((t) => !seen.contains(t.uid))
            .toList();
        if (more.isNotEmpty) {
          rows.add(RecoRow('Ещё от $a', more));
          seen.addAll(more.map((t) => t.uid));
        }
      } catch (_) {}
    }

    // «Для вас» — микс похожих на топ-треки и лайки.
    final seeds = <Track>[
      ...topTracks.take(3).map((e) => e.key),
      ...liked.take(2),
    ];
    final pool = <String, Track>{};
    for (final s in seeds.take(4)) {
      final sim = await similarTo(s);
      for (final t in sim) {
        if (!seen.contains(t.uid)) pool[t.uid] = t;
      }
    }
    if (pool.isNotEmpty) {
      rows.add(RecoRow('Для вас — на основе вашей библиотеки',
          pool.values.take(24).toList()));
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
