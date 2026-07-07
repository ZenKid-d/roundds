import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/artwork.dart';
import '../../data/recs/recs_store.dart';

/// Экран дизлайков: треки, исключённые из рекомендаций. Дизлайк можно снять.
class DislikesScreen extends ConsumerWidget {
  const DislikesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(recsStoreProvider);
    final items = store.dislikedTracks;
    return Scaffold(
      appBar: AppBar(title: const Text('Дизлайки')),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Пусто. Дизлайкнутые треки не попадают в рекомендации.\n'
                  'Дизлайк — на плеере или в меню трека (⋮).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.white45),
                ),
              ),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final t = items[i];
                return ListTile(
                  leading: Artwork(t.artworkUrl,
                      size: 46, seed: t.uid, radius: 10),
                  title: Text(t.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(t.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.white45)),
                  trailing: IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: 'Вернуть в рекомендации',
                    onPressed: () =>
                        store.undislikeKey(RecsStore.keyFor(t)),
                  ),
                );
              },
            ),
    );
  }
}
