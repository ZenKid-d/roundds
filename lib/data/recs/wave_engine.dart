/// Recs v2 — движок «Моей волны». Собирает кандидатов из провайдеров, резолвит
/// в играбельные треки, фильтрует дизлайки/cooldown, скорит по профилю+характеру,
/// раскладывает с anti-repetition и exploration-квотой. Держит состояние сессии
/// для real-time адаптации: скип/лайк меняют направление и хвост очереди.
library;

import '../../domain/models/track.dart';
import '../aggregator.dart';
import 'candidates/candidate_provider.dart';
import 'recs_dedup.dart';
import 'recs_signals.dart';
import 'recs_store.dart';
import 'scorer.dart';
import 'taste_profile.dart';
import 'wave_constraints.dart';
import 'wave_mode.dart';

/// Кандидат волны: играбельный трек + фичи скоринга.
class WaveCandidate {
  WaveCandidate(this.track, {this.tags = const [], this.popularity = 0.0});
  final Track track;
  final List<String> tags;
  final double popularity;

  String get artistKey => RecsDedup.normalize(track.artist);
  String get dedupKey => RecsDedup.normKey(track.artist, track.title);
}

class WaveEngine {
  WaveEngine({
    required RecsStore store,
    required Aggregator aggregator,
    required List<CandidateProvider> providers,
    required List<Track> Function() favorites,
    required WaveMode Function() mode,
  })  : _store = store,
        _aggregator = aggregator,
        _providers = providers,
        _favorites = favorites,
        _mode = mode;

  final RecsStore _store;
  final Aggregator _aggregator;
  final List<CandidateProvider> _providers;
  final List<Track> Function() _favorites;
  final WaveMode Function() _mode;

  /// Максимум сетевых резолвов (RawCandidate без готового трека) за генерацию.
  static const int _maxResolvePerGen = 14;

  // --- состояние сессии ---
  TasteProfile _profile = TasteProfile.empty;
  final Map<String, double> _sessionArtist = {}; // real-time оверрайды short
  final List<String> _recentArtists = []; // хвост уже проигранного (для gap)
  final Set<String> _served = {}; // dedup-ключи, уже выданные в волну
  String? _lastSkipArtist;
  int _consecutiveSkips = 0;

  /// Живой профиль = база + сессионные оверрайды (real-time направление).
  TasteProfile get _liveProfile =>
      _profile.withSessionOverrides(_sessionArtist);

  Future<void> _resetSession() async {
    _profile = await _store.buildProfile();
    _sessionArtist.clear();
    _recentArtists.clear();
    _served.clear();
    _lastSkipArtist = null;
    _consecutiveSkips = 0;
  }

  /// Старт волны: первый буфер из профиля (+ опциональный сид-трек).
  Future<List<Track>> start({Track? seed, int limit = 18}) async {
    await _resetSession();
    final seeds = <Track>[
      if (seed != null) seed,
      ..._favorites().take(4),
    ];
    return _generate(seeds, limit: limit);
  }

  /// Докрутка очереди (radioExtender) / регенерация хвоста от текущего трека.
  Future<List<Track>> extend(Track seed, {int limit = 12}) async {
    // Лениво строим профиль, если волну не стартовали явно (напр. «радио от трека»).
    if (_profile.heardArtists.isEmpty && _served.isEmpty) {
      _profile = await _store.buildProfile();
    }
    final seeds = <Track>[seed, ..._favorites().take(2)];
    return _generate(seeds, limit: limit);
  }

  Future<List<Track>> _generate(List<Track> seeds, {required int limit}) async {
    final pool = await _gather(seeds);
    final cooldown = await _store.cooldownMap();
    final ranked = rankWave(
      pool,
      profile: _liveProfile,
      cooldown: cooldown,
      dislikedKeys: _store.dislikedKeys,
      weights: _mode().weights,
      constraints: _mode().constraints,
      recentArtists: List.of(_recentArtists),
      servedKeys: Set.of(_served),
      nowSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      limit: limit,
    );
    for (final t in ranked) {
      _served.add(RecsDedup.normKey(t.artist, t.title));
      _recentArtists.add(RecsDedup.normalize(t.artist));
    }
    return ranked;
  }

  /// I/O: провайдеры → резолв в играбельные треки. Дизлайки/дедуп/скоринг —
  /// дальше в [rankWave].
  Future<List<WaveCandidate>> _gather(List<Track> seeds) async {
    final query = CandidateQuery(
      seeds: seeds,
      seedArtists: _profile.topArtists(limit: 6),
      seedTags: _profile.topTags(limit: 4),
      limitPerSeed: 15,
    );
    final available = <CandidateProvider>[];
    for (final p in _providers) {
      if (await p.isAvailable) available.add(p);
    }
    final results = await Future.wait(available.map((p) async {
      try {
        return await p.fetch(query);
      } catch (_) {
        return const <RawCandidate>[];
      }
    }));
    final raw = results.expand((e) => e).toList();

    // Дедуп сырых по нормключу; готовые треки — сразу, остальные — на резолв.
    final seen = <String>{};
    final resolved = <WaveCandidate>[];
    final toResolve = <RawCandidate>[];
    for (final c in raw) {
      if (c.artist.isEmpty || c.title.isEmpty) continue;
      if (!seen.add(c.dedupKey)) continue;
      final r = c.resolved;
      if (r != null) {
        resolved.add(WaveCandidate(r, tags: c.tags, popularity: c.popularity));
      } else {
        toResolve.add(c);
      }
    }
    toResolve.sort((a, b) => b.weight.compareTo(a.weight));

    final batch = toResolve.take(_maxResolvePerGen).toList();
    final extra = await Future.wait(batch.map((c) async {
      try {
        final found =
            await _aggregator.search('${c.artist} ${c.title}', perSource: 1);
        return found.isEmpty
            ? null
            : WaveCandidate(found.first, tags: c.tags, popularity: c.popularity);
      } catch (_) {
        return null;
      }
    }));
    resolved.addAll(extra.whereType<WaveCandidate>());
    return resolved;
  }

  // --- real-time петля ---

  /// Сигнал завершения трека из плеера. Возвращает true, если хвост очереди
  /// стоит перегенерировать (был скип).
  bool noteEnded(Track track, int playedMs, int durMs) {
    final kind =
        RecsSignals.classifyPlayback(playedMs: playedMs, durationMs: durMs);
    final aKey = RecsDedup.normalize(track.artist);
    if (kind == SignalKind.skipHard || kind == SignalKind.skipSoft) {
      _bumpSession(aKey, kind == SignalKind.skipHard ? -1.2 : -0.5);
      if (_lastSkipArtist == aKey) {
        _consecutiveSkips++;
      } else {
        _consecutiveSkips = 1;
        _lastSkipArtist = aKey;
      }
      // Два скипа одного направления подряд — резко топим направление.
      if (_consecutiveSkips >= 2) _bumpSession(aKey, -1.5);
      return true;
    }
    if (kind == SignalKind.complete) {
      _bumpSession(aKey, 0.6);
      _consecutiveSkips = 0;
      _lastSkipArtist = null;
    }
    return false;
  }

  /// Лайк усиливает направление в сессии (мгновенно).
  void noteLike(Track track) =>
      _bumpSession(RecsDedup.normalize(track.artist), 1.2);

  void _bumpSession(String artistKey, double delta) {
    if (artistKey.isEmpty) return;
    _sessionArtist[artistKey] = (_sessionArtist[artistKey] ?? 0) + delta;
  }

  // --- чистый ранкер (тестируемо) ---

  /// Фильтрует (дизлайки/выданное), скорит, гарантирует долю exploration и
  /// раскладывает с anti-repetition. Возвращает готовую последовательность.
  static List<Track> rankWave(
    List<WaveCandidate> cands, {
    required TasteProfile profile,
    required Map<String, int> cooldown,
    required Set<String> dislikedKeys,
    required ScoreWeights weights,
    required WaveConstraints constraints,
    required List<String> recentArtists,
    required Set<String> servedKeys,
    required int nowSec,
    int limit = 18,
  }) {
    int? agoOf(WaveCandidate c) {
      final last = cooldown[RecsStore.keyFor(c.track)];
      return last == null ? null : nowSec - last;
    }

    final scorer = Scorer(profile, weights: weights);
    final scored = <({WaveCandidate c, double s, bool explore})>[];
    for (final c in cands) {
      if (dislikedKeys.contains(RecsStore.keyFor(c.track))) continue;
      if (servedKeys.contains(c.dedupKey)) continue;
      final sc = scorer.score(ScoreCandidate(
        artistKey: c.artistKey,
        tags: c.tags,
        popularity: c.popularity,
        lastPlayedSecAgo: agoOf(c),
      ));
      scored.add((c: c, s: sc, explore: !profile.isKnownArtist(c.artistKey)));
    }
    scored.sort((a, b) => b.s.compareTo(a.s));

    // Гарантируем долю незнакомых артистов (exploration) даже при слабом w_nov.
    final exploit = [for (final e in scored) if (!e.explore) e.c];
    final explore = [for (final e in scored) if (e.explore) e.c];
    final merged =
        _mergeForExploration(exploit, explore, weights.explorationShare);

    return WaveSequencer.arrange<WaveCandidate>(
      merged,
      artistKeyOf: (c) => c.artistKey,
      dedupKeyOf: (c) => c.dedupKey,
      lastPlayedSecAgoOf: agoOf,
      constraints: constraints,
      recentArtists: recentArtists,
      limit: limit,
    ).map((c) => c.track).toList();
  }

  /// Сливает exploit/explore-списки так, чтобы доля explore ≈ [share].
  static List<WaveCandidate> _mergeForExploration(
      List<WaveCandidate> exploit, List<WaveCandidate> explore, double share) {
    final s = share.clamp(0.0, 1.0);
    if (explore.isEmpty || s <= 0) return [...exploit, ...explore];
    if (exploit.isEmpty || s >= 1) return [...explore, ...exploit];
    final out = <WaveCandidate>[];
    var ei = 0;
    var xi = 0;
    var explorePlaced = 0;
    while (ei < exploit.length || xi < explore.length) {
      final wantExplore = ((out.length + 1) * s).ceil() > explorePlaced;
      if (wantExplore && xi < explore.length) {
        out.add(explore[xi++]);
        explorePlaced++;
      } else if (ei < exploit.length) {
        out.add(exploit[ei++]);
      } else if (xi < explore.length) {
        out.add(explore[xi++]);
        explorePlaced++;
      }
    }
    return out;
  }
}
