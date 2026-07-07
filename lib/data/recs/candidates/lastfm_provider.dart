/// Recs v2 — LastFmProvider: основной граф похожести (track.getSimilar +
/// tag.getTopTracks). Доступен только при пользовательском API-ключе (Q2);
/// ответы кэшируются в similar_cache (TTL 7 дней).
library;

import 'dart:convert';

import '../../lastfm_service.dart';
import '../recs_store.dart';
import 'candidate_provider.dart';

class LastFmProvider implements CandidateProvider {
  LastFmProvider(this._lastfm, this._store);

  final LastfmService _lastfm;
  final RecsStore _store;

  @override
  String get id => 'lastfm';

  @override
  Future<bool> get isAvailable async => _lastfm.hasApiKey;

  @override
  Future<List<RawCandidate>> fetch(CandidateQuery query) async {
    if (!_lastfm.hasApiKey) return const [];
    final out = <RawCandidate>[];
    for (final seed in query.seeds) {
      final key = 'lastfm:tsim:${seed.artist}|${seed.title}'.toLowerCase();
      out.addAll(await _cached(
        key,
        () async => [
          for (final s
              in await _lastfm.getSimilarTracks(seed.artist, seed.title,
                  limit: query.limitPerSeed))
            RawCandidate(artist: s.artist, title: s.title, weight: s.weight),
        ],
      ));
    }
    for (final tag in query.seedTags) {
      final key = 'lastfm:tagtop:$tag'.toLowerCase();
      out.addAll(await _cached(key, () async {
        final tracks =
            await _lastfm.getTagTopTracks(tag, limit: query.limitPerSeed);
        final n = tracks.length;
        return [
          for (var i = 0; i < n; i++)
            RawCandidate(
              artist: tracks[i].artist,
              title: tracks[i].title,
              tags: [tag],
              popularity: 1.0 - i / n, // порядок Last.fm = популярность
            ),
        ];
      }));
    }
    // «Популярное»: хиты любимых артистов профиля (популярное во вкусе).
    if (query.wantPopular) {
      for (final artist in query.seedArtists) {
        final key = 'lastfm:artisttop:$artist'.toLowerCase();
        out.addAll(await _cached(key, () async {
          final tracks = await _lastfm.getArtistTopTracks(artist, limit: 12);
          final n = tracks.length;
          return [
            for (var i = 0; i < n; i++)
              RawCandidate(
                artist: tracks[i].artist,
                title: tracks[i].title,
                weight: 1.0 - i / n, // приоритет резолва
                popularity: 1.0 - i / n,
              ),
          ];
        }));
      }
    }
    return out;
  }

  /// Читает из кэша по [key]; при промахе зовёт [fetch] и кладёт в кэш.
  Future<List<RawCandidate>> _cached(
      String key, Future<List<RawCandidate>> Function() fetch) async {
    final cached = await _store.similarCacheGet(key);
    if (cached != null) return _decode(cached);
    final fresh = await fetch();
    if (fresh.isNotEmpty) {
      await _store.similarCachePut(key, _encode(fresh));
    }
    return fresh;
  }

  static String _encode(List<RawCandidate> cs) => jsonEncode([
        for (final c in cs)
          {
            'a': c.artist,
            't': c.title,
            'w': c.weight,
            'g': c.tags,
            'p': c.popularity
          }
      ]);

  static List<RawCandidate> _decode(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          RawCandidate(
            artist: (e['a'] as String?) ?? '',
            title: (e['t'] as String?) ?? '',
            weight: (e['w'] as num?)?.toDouble() ?? 0,
            tags: [for (final g in (e['g'] as List? ?? const [])) g as String],
            popularity: (e['p'] as num?)?.toDouble() ?? 0,
          ),
      ].where((c) => c.artist.isNotEmpty && c.title.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }
}
