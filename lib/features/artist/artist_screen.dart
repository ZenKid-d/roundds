import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/mini_player.dart';
import '../../core/widgets/track_card.dart';
import '../../domain/models/track.dart';

final _artistTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, artist) async {
  return ref.read(aggregatorProvider).search(artist);
});

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.artist});
  final String artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(_artistTracksProvider(artist));
    return Scaffold(
      appBar: AppBar(
        title: Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.radio),
            tooltip: 'Радио по артисту',
            onPressed: () {
              final list = tracks.value;
              if (list != null && list.isNotEmpty) {
                ref.read(playbackProvider).startRadio(list.first, list);
              }
            },
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: tracks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Не удалось загрузить: $e',
                style: TextStyle(color: AppColors.white45)),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Text('Ничего не найдено',
                  style: TextStyle(color: AppColors.white45)),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => TrackRow(
              track: list[i],
              onTap: () => playTrack(ref, context, list[i], queue: list),
            ),
          );
        },
      ),
    );
  }
}
