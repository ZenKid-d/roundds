/// Recs v2 — движок «Моей волны». Собирает кандидатов из провайдеров, резолвит
/// в играбельные треки, фильтрует дизлайки/cooldown, скорит по профилю+характеру,
/// раскладывает с anti-repetition и exploration-квотой. Держит состояние сессии
/// для real-time адаптации: скип/лайк меняют направление и хвост очереди.
library;

import '../../domain/models/track.dart';
import '../aggregator.dart';
import '../recommendation_service.dart' show RecoRow;
import 'candidates/candidate_provider.dart';
import 'recs_dedup.dart';
import 'recs_signals.dart';
import 'recs_store.dart';
import 'scorer.dart';
import 'taste_profile.dart';
import 'wave_constraints.dart';
import 'wave_mode.dart';
import 'wave_mood.dart';

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
    required WaveMood Function() mood,
    required Set<String> Function() blacklist,
  })  : _store = store,
        _aggregator = aggregator,
        _providers = providers,
        _favorites = favorites,
        _mode = mode,
        _moodOf = mood,
        _blacklist = blacklist;

  final RecsStore _store;
  final Aggregator _aggregator;
  final List<CandidateProvider> _providers;
  final List<Track> Function() _favorites;
  final WaveMode Function() _mode;
  final WaveMood Function() _moodOf;

  /// Нормализованные ключи забаненных артистов (из библиотеки).
  final Set<String> Function() _blacklist;

  /// Максимум сетевых резолвов (RawCandidate без готового трека) за генерацию.
  static const int _maxResolvePerGen = 14;

  /// Границы длительности «музыкального трека».
  static const int _minTrackSec = 45; // ниже — шортсы/клипы
  static const int _maxTrackSec = 12 * 60; // выше — миксы/стримы/подкасты

  /// Похоже ли на музыкальный трек, а не на обычное видео. Основной источник
  /// «видео» в волне — YouTube related (Piped relatedStreams не фильтрует по
  /// музыке), поэтому чистим централизованно по длительности; неизвестная
  /// длительность — не отбрасываем.
  static bool looksLikeMusic(Track t) {
    final d = t.duration;
    if (d == null) return true;
    final s = d.inSeconds;
    return s >= _minTrackSec && s <= _maxTrackSec;
  }

  // Высокоточные маркеры «мусорных» версий: редко встречаются в названиях/именах
  // настоящих релизов, поэтому риск ложных срабатываний низкий (не режем «cover»/
  // «live»/«remix» — там много легитимного).
  static const List<String> _junkTitleMarkers = [
    'karaoke', 'nightcore', 'type beat', 'made famous by',
    'originally performed', 'in the style of', '8d audio', 'sped up',
    'sped-up', 'slowed + reverb', 'slowed and reverb', 'cover version',
    'ringtone', 'guitar backing track', 'drumless', 'metal cover',
  ];
  static const List<String> _junkArtistMarkers = [
    'karaoke', 'tribute', 'made famous', 'vitamin string quartet',
    'nightcore', 'type beat', 'cover band', '8-bit', '8 bit',
    'lullaby versions', 'rockabye baby',
  ];

  /// Явный «мусор»: каверы/караоке/nightcore/8D/ускоренные/type beat и т.п.
  static bool looksLikeJunk(Track t) {
    final title = t.title.toLowerCase();
    for (final m in _junkTitleMarkers) {
      if (title.contains(m)) return true;
    }
    final artist = t.artist.toLowerCase();
    for (final m in _junkArtistMarkers) {
      if (artist.contains(m)) return true;
    }
    return false;
  }

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
    final moodTags = _moodOf().tags;
    final pool = await _gather(
      seeds,
      seedArtists: _profile.topArtists(limit: 6),
      // Настроение подмешивает свои теги в сиды: tag.getTopTracks отдаст треки
      // этого настроения (при наличии Last.fm).
      seedTags: [..._profile.topTags(limit: 4), ...moodTags],
      // «Популярное»: тянем хиты любимых артистов (популярное во вкусе).
      wantPopular: _mode() == WaveMode.popular,
    );
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
      moodTags: moodTags.toSet(),
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
  Future<List<WaveCandidate>> _gather(
    List<Track> seeds, {
    List<String> seedArtists = const [],
    List<String> seedTags = const [],
    bool wantPopular = false,
  }) async {
    final query = CandidateQuery(
      seeds: seeds,
      seedArtists: seedArtists,
      seedTags: seedTags,
      limitPerSeed: 15,
      wantPopular: wantPopular,
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
            await _aggregator.search('${c.artist} ${c.title}', perSource: 3);
        // Берём результат, реально совпадающий с кандидатом (точный ключ, иначе
        // fuzzy). Без проверки резолв часто подсовывает кавер/караоке/ускоренный/
        // чужой трек — это и есть мусор.
        Track? exact;
        Track? fuzzy;
        for (final t in found) {
          if (exact == null &&
              RecsDedup.normKey(c.artist, c.title) ==
                  RecsDedup.normKey(t.artist, t.title)) {
            exact = t;
          } else if (fuzzy == null &&
              RecsDedup.resolvesTo(c.artist, c.title, t.artist, t.title)) {
            fuzzy = t;
          }
        }
        final match = exact ?? fuzzy;
        return match == null
            ? null
            : WaveCandidate(match, tags: c.tags, popularity: c.popularity);
      } catch (_) {
        return null;
      }
    }));
    resolved.addAll(extra.whereType<WaveCandidate>());
    // Финальная чистка: только музыка, без мусорных версий и забаненных артистов.
    final blocked = _blacklist();
    return [
      for (final c in resolved)
        if (looksLikeMusic(c.track) &&
            !looksLikeJunk(c.track) &&
            !blocked.contains(c.artistKey))
          c
    ];
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

  // --- ряды главной v2 (движок, а не сырые similar-эндпоинты) ---

  /// Ряды для главной: «Для вас» (топ по долгосрочному профилю), «Новое для
  /// тебя» (чистый exploration) и «Похожее на {артист}» (сид ротируется по дню).
  /// Не трогает состояние живой волны.
  Future<List<RecoRow>> buildHomeRows({int perRow = 20}) async {
    final profile = await _store.buildProfile();
    final favs = _favorites();
    final cooldown = await _store.cooldownMap();
    final disliked = _store.dislikedKeys;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rows = <RecoRow>[];

    final pool = await _gather(
      favs.take(5).toList(),
      seedArtists: profile.topArtists(limit: 6),
      seedTags: profile.topTags(limit: 4),
    );

    // 1) «Для вас» — топ скоринга по долгосрочному профилю (знакомое любимое).
    final forYou = rankWave(
      pool,
      profile: profile,
      cooldown: cooldown,
      dislikedKeys: disliked,
      weights: ScoreWeights.favorite,
      constraints: WaveConstraints.balanced,
      recentArtists: const [],
      servedKeys: const {},
      nowSec: nowSec,
      limit: perRow,
    );
    if (forYou.length >= 4) rows.add(RecoRow('Для вас', forYou));

    // 2) «Новое для тебя» — только незнакомые артисты (чистый exploration),
    //    без пересечения с «Для вас».
    final explorePool =
        pool.where((c) => !profile.isKnownArtist(c.artistKey)).toList();
    final fresh = rankWave(
      explorePool,
      profile: profile,
      cooldown: cooldown,
      dislikedKeys: disliked,
      weights: ScoreWeights.unfamiliar,
      constraints: WaveConstraints.balanced,
      recentArtists: const [],
      servedKeys: {
        for (final t in forYou) RecsDedup.normKey(t.artist, t.title)
      },
      nowSec: nowSec,
      limit: perRow,
    );
    if (fresh.length >= 4) rows.add(RecoRow('Новое для тебя', fresh));

    // 3) «Похожее на {артист}» — сид ротируется ежедневно из топ-артистов.
    final topArtists = profile.topArtists(limit: 8);
    if (topArtists.isNotEmpty) {
      final daySeed =
          DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
      final artistKey = topArtists[daySeed % topArtists.length];
      final artistSeeds = favs
          .where((t) => RecsDedup.normalize(t.artist) == artistKey)
          .take(3)
          .toList();
      if (artistSeeds.isNotEmpty) {
        final aPool = await _gather(artistSeeds);
        final sim = rankWave(
          aPool,
          profile: profile,
          cooldown: cooldown,
          dislikedKeys: disliked,
          weights: ScoreWeights.balanced,
          constraints: WaveConstraints.balanced,
          recentArtists: const [],
          servedKeys: const {},
          nowSec: nowSec,
          limit: perRow,
        );
        if (sim.length >= 4) {
          rows.add(RecoRow('Похожее на ${artistSeeds.first.artist}', sim));
        }
      }
    }
    return rows;
  }

  // --- дневные плейлисты (кэш на сутки) ---

  /// «Плейлист дня» (~65% любимого + ~35% открытий) и «Дежавю» (незнакомые
  /// артисты из 2-hop графа). Генерируются раз в сутки, кэшируются с датой.
  /// Премьера (свежие релизы) — отдельная под-фаза 5b.
  Future<List<RecoRow>> dailyPlaylists({int size = 30}) async {
    final day = _todayKey();
    final cachedMix = await _store.dailyGet('mix', day);
    final cachedDejavu = await _store.dailyGet('dejavu', day);
    if (cachedMix != null && cachedDejavu != null) {
      return [
        if (cachedMix.isNotEmpty) RecoRow('Плейлист дня', cachedMix),
        if (cachedDejavu.isNotEmpty) RecoRow('Дежавю', cachedDejavu),
      ];
    }

    final profile = await _store.buildProfile();
    final favs = _favorites();
    final cooldown = await _store.cooldownMap();
    final disliked = _store.dislikedKeys;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final pool = await _gather(
      favs.take(6).toList(),
      seedArtists: profile.topArtists(limit: 8),
      seedTags: profile.topTags(limit: 4),
    );

    // «Плейлист дня»: ~65% знакомого любимого + ~35% открытий (exploration 0.35).
    final mix = rankWave(
      pool,
      profile: profile,
      cooldown: cooldown,
      dislikedKeys: disliked,
      weights: const ScoreWeights(
          wSim: 1.2, wNov: 0.4, wRep: 0.7, explorationShare: 0.35),
      constraints: WaveConstraints.balanced,
      recentArtists: const [],
      servedKeys: const {},
      nowSec: nowSec,
      limit: size,
    );
    await _store.dailyPut('mix', day, mix);

    // «Дежавю»: 2-hop — незнакомые артисты (ноль прослушиваний) из графа похожести.
    final firstHopUnknown = pool
        .where((c) => !profile.isKnownArtist(c.artistKey))
        .map((c) => c.track)
        .take(6)
        .toList();
    final dejavu = <Track>[];
    if (firstHopUnknown.isNotEmpty) {
      final pool2 = await _gather(firstHopUnknown);
      final unknown2 =
          pool2.where((c) => !profile.isKnownArtist(c.artistKey)).toList();
      dejavu.addAll(rankWave(
        unknown2,
        profile: profile,
        cooldown: cooldown,
        dislikedKeys: disliked,
        weights: ScoreWeights.unfamiliar,
        constraints: WaveConstraints.balanced,
        recentArtists: const [],
        servedKeys: {
          for (final t in mix) RecsDedup.normKey(t.artist, t.title)
        },
        nowSec: nowSec,
        limit: size,
      ));
    }
    await _store.dailyPut('dejavu', day, dejavu);

    return [
      if (mix.isNotEmpty) RecoRow('Плейлист дня', mix),
      if (dejavu.isNotEmpty) RecoRow('Дежавю', dejavu),
    ];
  }

  String _todayKey() {
    final d = DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
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
    Set<String> moodTags = const {},
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
      // Бонус за совпадение тега с настроением (приблизительно, при Last.fm).
      final moodBonus =
          moodTags.isNotEmpty && c.tags.any(moodTags.contains) ? 0.6 : 0.0;
      scored.add((
        c: c,
        s: sc + moodBonus,
        explore: !profile.isKnownArtist(c.artistKey)
      ));
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
