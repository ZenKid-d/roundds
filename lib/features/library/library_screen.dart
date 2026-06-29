import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/track_card.dart';
import '../../domain/models/playlist.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _showQueue = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _Toggle(
                  label: 'Плейлисты',
                  active: !_showQueue,
                  onTap: () => setState(() => _showQueue = false)),
              const SizedBox(width: 8),
              _Toggle(
                  label: 'Очередь',
                  active: _showQueue,
                  onTap: () => setState(() => _showQueue = true)),
              const Spacer(),
              if (!_showQueue)
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _createPlaylist,
                ),
            ],
          ),
        ),
        Expanded(child: _showQueue ? const _QueueView() : _PlaylistsView()),
      ],
    );
  }

  Future<void> _createPlaylist() async {
    final name = await _askName(context, 'Новый плейлист');
    if (name != null && name.isNotEmpty) {
      await ref.read(libraryProvider).createPlaylist(name);
    }
  }
}

Future<String?> _askName(BuildContext context, String title,
    {String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface2,
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Название'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Сохранить')),
      ],
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? Colors.white24 : Colors.transparent),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w500 : FontWeight.w400,
              color: active ? Colors.white : AppColors.white45,
            )),
      ),
    );
  }
}

class _PlaylistsView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(libraryProvider).playlists;
    if (playlists.isEmpty) {
      return Center(
        child: Text('Нет плейлистов.\nНажмите + чтобы создать.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.white45)),
      );
    }
    return ListView.builder(
      itemCount: playlists.length,
      itemBuilder: (_, i) {
        final pl = playlists[i];
        return ListTile(
          leading: SizedBox(
            width: 52,
            height: 52,
            child: Artwork(pl.cover?.artworkUrl, seed: pl.id, radius: 12),
          ),
          title: Text(pl.name, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text('${pl.tracks.length} треков',
              style: TextStyle(color: AppColors.white45, fontSize: 12)),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _playlistMenu(context, ref, pl),
          ),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PlaylistScreen(playlistId: pl.id),
          )),
        );
      },
    );
  }

  void _playlistMenu(BuildContext context, WidgetRef ref, PlaylistX pl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface2,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Переименовать'),
              onTap: () async {
                Navigator.pop(context);
                final name = await _askName(context, 'Переименовать',
                    initial: pl.name);
                if (name != null && name.isNotEmpty) {
                  await ref.read(libraryProvider).renamePlaylist(pl.id, name);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить'),
              onTap: () {
                ref.read(libraryProvider).deletePlaylist(pl.id);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pl = ref
        .watch(libraryProvider)
        .playlists
        .firstWhere((e) => e.id == playlistId,
            orElse: () => PlaylistX(id: playlistId, name: 'Плейлист'));
    return Scaffold(
      appBar: AppBar(title: Text(pl.name)),
      body: pl.tracks.isEmpty
          ? Center(
              child: Text('Плейлист пуст',
                  style: TextStyle(color: AppColors.white45)))
          : ListView.builder(
              itemCount: pl.tracks.length,
              itemBuilder: (_, i) => TrackRow(
                track: pl.tracks[i],
                onTap: () =>
                    playTrack(ref, context, pl.tracks[i], queue: pl.tracks),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => ref
                      .read(libraryProvider)
                      .removeFromPlaylist(playlistId, pl.tracks[i]),
                ),
              ),
            ),
    );
  }
}

class _QueueView extends ConsumerWidget {
  const _QueueView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pc = ref.watch(playbackProvider);
    final queue = pc.queue;
    if (queue.isEmpty) {
      return Center(
        child: Text('Очередь пуста',
            style: TextStyle(color: AppColors.white45)),
      );
    }
    return ReorderableListView.builder(
      itemCount: queue.length,
      onReorder: pc.reorderQueue,
      itemBuilder: (_, i) {
        final t = queue[i];
        return TrackRow(
          key: ValueKey(t.uid),
          track: t,
          active: t.uid == pc.current?.uid,
          onTap: () => playTrack(ref, context, t, queue: queue,
              openPlayer: false),
          trailing: const Icon(Icons.drag_handle),
        );
      },
    );
  }
}
