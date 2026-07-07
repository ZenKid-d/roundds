/// Recs v2 — Riverpod-провайдеры движка: профиль вкуса и набор источников
/// кандидатов. Собираются поверх существующего DI-графа (core/providers.dart).
/// Провайдеры кандидатов сами возвращают пусто, если недоступны (нет ключа
/// Last.fm / токена Яндекса / выключенный источник) — движок работает и без них.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/models/source_type.dart';
import 'candidates/candidate_provider.dart';
import 'candidates/lastfm_provider.dart';
import 'candidates/source_candidate_providers.dart';
import 'taste_profile.dart';
import 'wave_engine.dart';
import 'wave_mode.dart';

/// Профиль вкуса из event log (строится из recsStore, снапшот кэшируется).
/// Пересчитывается по запросу; тяжёлое ранжирование пула — Фаза 3.
final tasteProfileProvider = FutureProvider<TasteProfile>((ref) async {
  final store = ref.watch(recsStoreProvider);
  return store.buildProfile();
});

/// Набор pluggable-провайдеров кандидатов.
final candidateProvidersProvider = Provider<List<CandidateProvider>>((ref) {
  final agg = ref.read(aggregatorProvider);
  bool enabled(SourceType t) => agg.enabled.contains(t);
  final store = ref.read(recsStoreProvider);
  return [
    LastFmProvider(ref.read(lastfmServiceProvider), store),
    SoundCloudRelatedProvider(
        ref.read(soundcloudSourceProvider), () => enabled(SourceType.soundcloud)),
    YtMusicRadioProvider(
        ref.read(youtubeSourceProvider), () => enabled(SourceType.youtube)),
    YandexSimilarProvider(
        ref.read(yandexSourceProvider), () => enabled(SourceType.yandex)),
    LocalHistoryProvider(store, () => ref.read(libraryProvider).liked),
  ];
});

/// Характер волны (Баланс/Любимое/Незнакомое/Популярное), персист в prefs.
final waveModeProvider = StateProvider<WaveMode>(
    (ref) => WaveModeX.fromId(ref.read(prefsProvider).getString('wave_mode')));

/// Движок «Моей волны» — держит сессию, докручивает очередь, адаптируется на
/// скип/лайк. Один на приложение.
final waveEngineProvider = Provider<WaveEngine>((ref) => WaveEngine(
      store: ref.read(recsStoreProvider),
      aggregator: ref.read(aggregatorProvider),
      providers: ref.read(candidateProvidersProvider),
      favorites: () => ref.read(libraryProvider).liked,
      mode: () => ref.read(waveModeProvider),
    ));
