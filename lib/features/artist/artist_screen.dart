import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/mini_player.dart';
import '../../core/widgets/track_card.dart';
import '../../domain/models/track.dart';
import '../../l10n/gen/app_localizations.dart';

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
    final following = ref.watch(libraryProvider).isFollowing(artist);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(following ? Icons.notifications_active : Icons.notifications_none),
            tooltip: following
                ? l10n.artistFollowingTooltip
                : l10n.artistFollowTooltip,
            onPressed: () {
              ref.read(libraryProvider).toggleFollow(artist);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(following
                      ? l10n.artistUnfollowSnack(artist)
                      : l10n.artistFollowSnack(artist))));
            },
          ),
          IconButton(
            icon: const Icon(Icons.radio),
            tooltip: l10n.artistRadioTooltip,
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
            child: Text(l10n.loadErrorGeneric(e.toString()),
                style: TextStyle(color: AppColors.white45)),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Text(l10n.artistTracksEmpty,
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
