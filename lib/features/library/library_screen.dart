import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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
  int _tab = 0; // 0 плейлисты, 1 любимое, 2 загрузки, 3 очередь
  static const _titles = ['Плейлисты', 'Любимое', 'Загрузки', 'Очередь'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _titles.length; i++) ...[
                        _Toggle(
                            label: _titles[i],
                            active: _tab == i,
                            onTap: () => setState(() => _tab = i)),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              if (_tab == 0) ...[
                IconButton(
                    icon: const Icon(Icons.library_add_outlined),
                    tooltip: 'Импорт плейлиста',
                    onPressed: _import),
                IconButton(
                    icon: const Icon(Icons.add), onPressed: _createPlaylist),
              ],
            ],
          ),
        ),
        Expanded(child: _bodyFor(_tab)),
      ],
    );
  }

  Widget _bodyFor(int t) => switch (t) {
        0 => _PlaylistsView(),
        1 => const _LikedView(),
        2 => const _DownloadsView(),
        _ => const _QueueView(),
      };

  Future<void> _createPlaylist() async {
    final name = await _askName(context, 'Новый плейлист');
    if (name != null && name.isNotEmpty) {
      await ref.read(libraryProvider).createPlaylist(name);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  void _showLoading() => showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

  Future<void> _import() async {
    final src = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface1,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Импорт плейлиста',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ),
            ListTile(
                leading: const FaIcon(FontAwesomeIcons.youtube,
                    color: Color(0xFFFF0000), size: 20),
                title: const Text('Из YouTube (ссылка)'),
                onTap: () => Navigator.pop(context, 'youtube')),
            ListTile(
                leading: const FaIcon(FontAwesomeIcons.youtube,
                    color: Color(0xFFFF0000), size: 20),
                title: const Text('Лайки YouTube Music (вход Google)'),
                onTap: () => Navigator.pop(context, 'ytlikes')),
            ListTile(
                leading: const FaIcon(FontAwesomeIcons.yandex,
                    color: Color(0xFFFFCC00), size: 20),
                title: const Text('Из Яндекса (мои плейлисты)'),
                onTap: () => Navigator.pop(context, 'yandex')),
          ],
        ),
      ),
    );
    if (src == 'youtube') {
      await _importYoutube();
    } else if (src == 'ytlikes') {
      await _importYoutubeLikes();
    } else if (src == 'yandex') {
      await _importYandex();
    }
  }

  Future<void> _importYoutubeLikes() async {
    _showLoading();
    try {
      final tracks =
          await ref.read(googleYtImportProvider).importLikedVideos();
      if (mounted) Navigator.pop(context);
      if (tracks.isEmpty) {
        _snack('Лайкнутых треков не найдено');
        return;
      }
      await ref
          .read(libraryProvider)
          .importPlaylist('YouTube — Мне понравилось', tracks);
      _snack('Импортировано лайков: ${tracks.length}');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Ошибка входа/импорта: $e');
    }
  }

  Future<void> _importYoutube() async {
    final url = await _askName(context, 'Ссылка на плейлист YouTube');
    if (url == null || url.isEmpty) return;
    _showLoading();
    try {
      final res = await ref.read(youtubeSourceProvider).importPlaylist(url);
      if (mounted) Navigator.pop(context);
      await ref.read(libraryProvider).importPlaylist(res.title, res.tracks);
      _snack('Импортировано: ${res.title} (${res.tracks.length} треков)');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Ошибка импорта: $e');
    }
  }

  Future<void> _importYandex() async {
    if (!ref.read(settingsProvider).hasYandexToken) {
      _snack('Сначала добавьте токен Яндекса в Настройках');
      return;
    }
    _showLoading();
    List<({int kind, String title, int count})> pls;
    try {
      pls = await ref.read(yandexSourceProvider).userPlaylists();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Ошибка: $e');
      return;
    }
    if (!mounted) return;
    final picked =
        await showModalBottomSheet<({int kind, String title, int count})>(
      context: context,
      backgroundColor: AppColors.surface1,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Выберите плейлист',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ),
            for (final p in pls)
              ListTile(
                  title: Text(p.title),
                  subtitle: Text('${p.count} треков'),
                  onTap: () => Navigator.pop(context, p)),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _showLoading();
    try {
      final tracks =
          await ref.read(yandexSourceProvider).playlistTracks(picked.kind);
      if (mounted) Navigator.pop(context);
      await ref.read(libraryProvider).importPlaylist(picked.title, tracks);
      _snack('Импортировано: ${picked.title} (${tracks.length} треков)');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Ошибка: $e');
    }
  }
}

class _LikedView extends ConsumerWidget {
  const _LikedView();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(libraryProvider).liked;
    if (liked.isEmpty) {
      return Center(
        child: Text('Нет лайкнутых треков',
            style: TextStyle(color: AppColors.white45)),
      );
    }
    return ListView.builder(
      itemCount: liked.length,
      itemBuilder: (_, i) => TrackRow(
        track: liked[i],
        onTap: () => playTrack(ref, context, liked[i], queue: liked),
        trailing: IconButton(
          icon: const Icon(Icons.favorite, color: Color(0xFFE24B4A)),
          onPressed: () => ref.read(libraryProvider).toggleLike(liked[i]),
        ),
      ),
    );
  }
}

class _DownloadsView extends ConsumerWidget {
  const _DownloadsView();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dl = ref.watch(downloadsProvider).downloads;
    if (dl.isEmpty) {
      return Center(
        child: Text('Нет скачанных треков',
            style: TextStyle(color: AppColors.white45)),
      );
    }
    return ListView.builder(
      itemCount: dl.length,
      itemBuilder: (_, i) => TrackRow(
        track: dl[i],
        onTap: () => playTrack(ref, context, dl[i], queue: dl),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: AppColors.white60),
          onPressed: () => ref.read(downloadsProvider).remove(dl[i].uid),
        ),
      ),
    );
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
