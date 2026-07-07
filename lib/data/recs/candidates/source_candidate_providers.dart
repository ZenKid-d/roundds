/// Recs v2 — провайдеры кандидатов поверх native related/similar-эндпоинтов
/// источников (переиспользуем то, что уже есть в v1) и локальной истории.
/// Каждый провайдер обрабатывает только сиды своего источника; ошибки внутри
/// не роняют остальные провайдеры.
library;

import '../../../domain/models/source_type.dart';
import '../../../domain/models/track.dart';
import '../../sources/soundcloud_source.dart';
import '../../sources/yandex_source.dart';
import '../../sources/youtube_music_source.dart';
import '../recs_store.dart';
import 'candidate_provider.dart';

RawCandidate _toCand(Track t) => RawCandidate(
      artist: t.artist,
      title: t.title,
      resolved: t,
    );

/// SoundCloud related-tracks для сидов-треков SoundCloud.
class SoundCloudRelatedProvider implements CandidateProvider {
  SoundCloudRelatedProvider(this._sc, this._enabled);
  final SoundcloudSource _sc;
  final bool Function() _enabled;

  @override
  String get id => 'sc_related';

  @override
  Future<bool> get isAvailable async => _enabled();

  @override
  Future<List<RawCandidate>> fetch(CandidateQuery query) async {
    if (!_enabled()) return const [];
    final out = <RawCandidate>[];
    for (final seed
        in query.seeds.where((s) => s.source == SourceType.soundcloud)) {
      try {
        final r = await _sc.related(seed.id, limit: query.limitPerSeed);
        out.addAll(r.map(_toCand));
      } catch (_) {}
    }
    return out;
  }
}

/// YouTube Music radio (InnerTube `next`) для YouTube-сидов. Внутренний API —
/// помечен experimental в дизайне; ошибки глушатся, остальные провайдеры живут.
class YtMusicRadioProvider implements CandidateProvider {
  YtMusicRadioProvider(this._yt, this._enabled);
  final YoutubeMusicSource _yt;
  final bool Function() _enabled;

  @override
  String get id => 'yt_radio';

  @override
  Future<bool> get isAvailable async => _enabled();

  @override
  Future<List<RawCandidate>> fetch(CandidateQuery query) async {
    if (!_enabled()) return const [];
    final out = <RawCandidate>[];
    for (final seed
        in query.seeds.where((s) => s.source == SourceType.youtube)) {
      try {
        final r = await _yt.relatedTo(seed.id, limit: query.limitPerSeed);
        out.addAll(r.map(_toCand));
      } catch (_) {}
    }
    return out;
  }
}

/// Похожие Яндекса — опционально, только если Яндекс включён и готов (токен).
class YandexSimilarProvider implements CandidateProvider {
  YandexSimilarProvider(this._ya, this._enabled);
  final YandexSource _ya;
  final bool Function() _enabled;

  @override
  String get id => 'yandex_similar';

  @override
  Future<bool> get isAvailable async => _enabled() && await _ya.isReady;

  @override
  Future<List<RawCandidate>> fetch(CandidateQuery query) async {
    if (!_enabled() || !await _ya.isReady) return const [];
    final out = <RawCandidate>[];
    for (final seed
        in query.seeds.where((s) => s.source == SourceType.yandex)) {
      try {
        final r = await _ya.similar(seed.id, limit: query.limitPerSeed);
        out.addAll(r.map(_toCand));
      } catch (_) {}
    }
    return out;
  }
}

/// Ресурфейсинг старых любимых, давно не звучавших (по cooldown). Работает
/// оффлайн — источник кандидатов без сети.
class LocalHistoryProvider implements CandidateProvider {
  LocalHistoryProvider(this._store, this._favorites,
      {this.resurfaceAfter = const Duration(days: 30)});
  final RecsStore _store;
  final List<Track> Function() _favorites;
  final Duration resurfaceAfter;

  @override
  String get id => 'local_history';

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<RawCandidate>> fetch(CandidateQuery query) async {
    final favs = _favorites();
    if (favs.isEmpty) return const [];
    final cooldown = await _store.cooldownMap();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final threshold = resurfaceAfter.inSeconds;
    final out = <RawCandidate>[];
    for (final t in favs) {
      final last = cooldown[RecsStore.keyFor(t)];
      if (last == null || nowSec - last >= threshold) {
        out.add(_toCand(t));
      }
    }
    return out;
  }
}
