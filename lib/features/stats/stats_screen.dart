import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/track_card.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final tracks = lib.topTracks(limit: 30);
    final artists = lib.topArtists(limit: 12);
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика')),
      body: tracks.isEmpty
          ? Center(
              child: Text('Пока нет прослушиваний',
                  style: TextStyle(color: AppColors.white45)),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Text('${lib.totalPlays}',
                          style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                              color: accent)),
                      const SizedBox(width: 10),
                      Text('всего\nпрослушиваний',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.white45)),
                    ],
                  ),
                ),
                if (artists.isNotEmpty) ...[
                  _header('Топ артистов'),
                  for (var i = 0; i < artists.length; i++)
                    ListTile(
                      leading: Text('${i + 1}',
                          style: TextStyle(color: AppColors.white45)),
                      title: Text(artists[i].key),
                      trailing: Text('${artists[i].value}',
                          style: TextStyle(color: accent)),
                    ),
                ],
                _header('Топ треков'),
                for (final e in tracks)
                  TrackRow(
                    track: e.key,
                    onTap: () => playTrack(ref, context, e.key,
                        queue: tracks.map((x) => x.key).toList()),
                    trailing: Text('${e.value}',
                        style: TextStyle(color: accent, fontSize: 13)),
                  ),
              ],
            ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Text(t,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      );
}
