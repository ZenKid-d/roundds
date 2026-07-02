import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/mini_player.dart';
import '../../core/widgets/track_card.dart';
import '../../domain/models/track.dart';
import 'artist_screen.dart';

/// Свежие треки от артистов, на которых подписан пользователь.
final followedNewReleasesProvider = FutureProvider<List<Track>>((ref) async {
  final artists = ref.read(libraryProvider).followedArtists.take(8).toList();
  final out = <Track>[];
  final seen = <String>{};
  for (final a in artists) {
    try {
      final r =
          await ref.read(aggregatorProvider).search('$a new music 2025');
      for (final t in r.take(6)) {
        if (seen.add(t.uid)) out.add(t);
      }
    } catch (_) {/* пропускаем артиста */}
  }
  return out;
});

class FollowedArtistsScreen extends ConsumerWidget {
  const FollowedArtistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followed = ref.watch(libraryProvider).followedArtists;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Мои артисты')),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: followed.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'Вы пока ни за кем не следите. Откройте страницу артиста и '
                  'нажмите «Следить».',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.white45),
                ),
              ),
            )
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text('Вы следите',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                ),
                SizedBox(
                  height: 104,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: followed.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, i) {
                      final a = followed[i];
                      return GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ArtistScreen(artist: a))),
                        child: SizedBox(
                          width: 72,
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 32,
                                backgroundColor: accent.withValues(alpha: 0.22),
                                child: Text(
                                  a.isNotEmpty ? a[0].toUpperCase() : '?',
                                  style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w600,
                                      color: accent),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(a,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
                  child: Text('🆕 Новинки от ваших артистов',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                ),
                _NewReleases(),
              ],
            ),
    );
  }
}

class _NewReleases extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rel = ref.watch(followedNewReleasesProvider);
    return rel.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text('Не удалось загрузить новинки',
            style: TextStyle(color: AppColors.white45)),
      ),
      data: (tracks) {
        if (tracks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Новинок не нашлось',
                style: TextStyle(color: AppColors.white45)),
          );
        }
        return Column(
          children: [
            for (final t in tracks)
              TrackRow(
                track: t,
                onTap: () => playTrack(ref, context, t, queue: tracks),
              ),
          ],
        );
      },
    );
  }
}
