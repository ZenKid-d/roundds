import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/mini_player.dart';
import '../../core/widgets/track_card.dart';
import '../../core/widgets/track_download_status.dart';
import '../../domain/models/playlist.dart';
import '../../domain/models/track.dart';
import '../common/track_list_screen.dart';

/// Строка фильтра медиатеки (по названию/артисту), в нижнем регистре.
final _libQueryProvider = StateProvider<String>((ref) => '');

enum PlaylistSort { recent, name, count }

final _plSortProvider = StateProvider<PlaylistSort>((ref) => PlaylistSort.recent);

bool _matchTrack(Track t, String q) =>
    q.isEmpty ||
    t.title.toLowerCase().contains(q) ||
    t.artist.toLowerCase().contains(q);

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _tab = 0; // 0 плейлисты, 1 любимое, 2 загрузки, 3 очередь
  static const _titles = ['Плейлисты', 'Любимое', 'Загрузки', 'Очередь'];
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _selectTab(int i) {
    setState(() => _tab = i);
    _search.clear();
    ref.read(_libQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final libQuery = ref.watch(_libQueryProvider);
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
                            onTap: () => _selectTab(i)),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              if (_tab == 0) ...[
                _PlaylistSortButton(),
                IconButton(
                    icon: const Icon(Icons.library_add_outlined),
                    tooltip: 'Импорт плейлиста',
                    onPressed: _import),
                IconButton(
                    icon: const Icon(Icons.add), onPressed: _createPlaylist),
              ],
              if (_tab == 1)
                IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: 'Скачать все лайки',
                  onPressed: () {
                    final liked = ref.read(libraryProvider).liked;
                    if (liked.isNotEmpty &&
                        !ref.read(downloadsProvider).playlistBusy) {
                      ref
                          .read(downloadsProvider)
                          .downloadPlaylist('Избранное', liked);
                      _snack('Скачивание «Избранное»…');
                    }
                  },
                ),
            ],
          ),
        ),
        if (_tab != 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: TextField(
              controller: _search,
              onChanged: (v) => ref.read(_libQueryProvider.notifier).state =
                  v.trim().toLowerCase(),
              decoration: InputDecoration(
                isDense: true,
                hintText: _tab == 0
                    ? 'Фильтр плейлистов'
                    : 'Фильтр по названию или артисту',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: libQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _search.clear();
                          ref.read(_libQueryProvider.notifier).state = '';
                        },
                      ),
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
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
            ListTile(
                leading: const Icon(Icons.format_list_bulleted),
                title: const Text('Из списка (текст)'),
                subtitle: Text('«Артист — Трек» построчно',
                    style: TextStyle(color: AppColors.white45, fontSize: 11)),
                onTap: () => Navigator.pop(context, 'list')),
            ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Из файла (.json)'),
                onTap: () => Navigator.pop(context, 'file')),
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
    } else if (src == 'file') {
      await _importPlaylistFile();
    } else if (src == 'list') {
      await _importFromList();
    }
  }

  Future<void> _importFromList() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: const Text('Импорт по списку'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Eminem — Lose Yourself\nThe Weeknd — Blinding Lights\n…',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Найти')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;
    _showLoading();
    final tracks = <Track>[];
    try {
      for (final line in lines) {
        try {
          final r = await ref.read(aggregatorProvider).search(line);
          if (r.isNotEmpty) tracks.add(r.first);
        } catch (_) {}
      }
    } finally {
      if (mounted) Navigator.pop(context); // индикатор
    }
    if (tracks.isEmpty) {
      _snack('Ничего не найдено по списку');
      return;
    }
    if (!mounted) return;
    final name = await _askName(context, 'Название плейлиста',
        initial: 'Мой список');
    if (name != null && name.isNotEmpty) {
      await ref.read(libraryProvider).importPlaylist(name, tracks);
      _snack('Импортировано: ${tracks.length} из ${lines.length}');
    }
  }

  Future<void> _importPlaylistFile() async {
    final file = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: ['json']);
    final path = file?.path;
    if (path == null) return;
    try {
      final data = jsonDecode(await File(path).readAsString());
      final map = (data as Map).cast<String, dynamic>();
      final name = (map['name'] as String?) ?? 'Импортированный плейлист';
      final tracks = ((map['tracks'] as List?) ?? [])
          .map((e) => Track.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (tracks.isEmpty) {
        _snack('Файл пуст или неверного формата');
        return;
      }
      await ref.read(libraryProvider).importPlaylist(name, tracks);
      _snack('Импортировано: $name (${tracks.length} треков)');
    } catch (e) {
      _snack('Ошибка импорта файла: $e');
    }
  }

  Future<void> _importYoutubeLikes() async {
    _showLoading();
    List<Track> tracks;
    try {
      tracks = await ref.read(googleYtImportProvider).importLikedVideos();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Ошибка входа/импорта: $e');
      return;
    }
    if (tracks.isEmpty) {
      _snack('Лайкнутых треков не найдено');
      return;
    }
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: const Text('Куда добавить лайки?'),
        content: Text('Найдено треков: ${tracks.length}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'playlist'),
              child: const Text('Отдельным плейлистом')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'liked'),
              child: const Text('В «Избранное»')),
        ],
      ),
    );
    if (choice == 'playlist') {
      await ref
          .read(libraryProvider)
          .importPlaylist('YouTube — Мне понравилось', tracks);
      _snack('Импортировано плейлистом: ${tracks.length}');
    } else if (choice == 'liked') {
      await ref.read(libraryProvider).addManyToLiked(tracks);
      _snack('Добавлено в Избранное: ${tracks.length}');
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
    final q = ref.watch(_libQueryProvider);
    final liked =
        ref.watch(libraryProvider).liked.where((t) => _matchTrack(t, q)).toList();
    if (liked.isEmpty) {
      return Center(
        child: Text(q.isEmpty ? 'Нет лайкнутых треков' : 'Ничего не найдено',
            style: TextStyle(color: AppColors.white45)),
      );
    }
    return ListView.builder(
      itemCount: liked.length,
      itemBuilder: (_, i) => TrackRow(
        track: liked[i],
        onTap: () => playTrack(ref, context, liked[i], queue: liked),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrackDownloadStatus(liked[i]),
            IconButton(
              icon: const Icon(Icons.favorite, color: Color(0xFFE24B4A)),
              onPressed: () => ref.read(libraryProvider).toggleLike(liked[i]),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadsView extends ConsumerWidget {
  const _DownloadsView();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.watch(downloadsProvider);
    final q = ref.watch(_libQueryProvider);
    // Недавно скачанные — сверху.
    final dl = ctl.downloads.reversed
        .where((t) => _matchTrack(t, q))
        .toList();
    final busy =
        ctl.inProgress.where((t) => _matchTrack(t, q)).toList();
    final accent = Theme.of(context).colorScheme.primary;

    if (dl.isEmpty && busy.isEmpty && !ctl.playlistBusy) {
      return Center(
        child: Text(q.isEmpty ? 'Нет скачанных треков' : 'Ничего не найдено',
            style: TextStyle(color: AppColors.white45)),
      );
    }
    return ListView(
      children: [
        if (ctl.playlistBusy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Скачивается плейлист: ${ctl.playlistName} · '
                    '${(ctl.playlistProgress * 100).round()}%',
                    style:
                        TextStyle(fontSize: 12.5, color: AppColors.white60)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                      value: ctl.playlistProgress, color: accent),
                ),
              ],
            ),
          ),
        for (final t in busy)
          ListTile(
            leading: SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                  value: ctl.progressFor(t.uid) == 0
                      ? null
                      : ctl.progressFor(t.uid),
                  strokeWidth: 2,
                  color: accent),
            ),
            title: Text(t.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${t.artist} · ${(ctl.progressFor(t.uid) * 100).round()}%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.white45, fontSize: 12)),
          ),
        for (final t in dl)
          TrackRow(
            track: t,
            onTap: () => playTrack(ref, context, t, queue: dl),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline, color: AppColors.white60),
              onPressed: () => ref.read(downloadsProvider).remove(t.uid),
            ),
          ),
      ],
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

int _plCreatedAt(String id) {
  final m = RegExp(r'pl_(\d+)').firstMatch(id);
  return m != null ? (int.tryParse(m.group(1)!) ?? 0) : 0;
}

/// Экспорт одного плейлиста в JSON-файл и «Поделиться».
Future<void> _exportPlaylist(PlaylistX pl) async {
  try {
    final data = {
      'roundds_playlist': 1,
      'name': pl.name,
      'tracks': pl.tracks.map((t) => t.toJson()).toList(),
    };
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final safe = pl.name.replaceAll(RegExp(r'[^\wА-Яа-яЁё -]'), '_');
    final file = File('${dir.path}/$safe.json');
    await file.writeAsString(json);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Roundds — плейлист «${pl.name}»',
      ),
    );
  } catch (_) {/* отмена/ошибка шаринга не критична */}
}

List<PlaylistX> _sortPlaylists(List<PlaylistX> list, PlaylistSort sort) {
  final l = List<PlaylistX>.from(list);
  switch (sort) {
    case PlaylistSort.name:
      l.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    case PlaylistSort.count:
      l.sort((a, b) => b.tracks.length - a.tracks.length);
    case PlaylistSort.recent:
      l.sort((a, b) => _plCreatedAt(b.id).compareTo(_plCreatedAt(a.id)));
  }
  return l;
}

class _PlaylistSortButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const labels = {
      PlaylistSort.recent: 'Недавно добавленные',
      PlaylistSort.name: 'По имени',
      PlaylistSort.count: 'По числу треков',
    };
    return PopupMenuButton<PlaylistSort>(
      icon: const Icon(Icons.sort),
      tooltip: 'Сортировка',
      onSelected: (v) => ref.read(_plSortProvider.notifier).state = v,
      itemBuilder: (_) => [
        for (final e in labels.entries)
          PopupMenuItem(
            value: e.key,
            child: Row(
              children: [
                Icon(
                    ref.read(_plSortProvider) == e.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18),
                const SizedBox(width: 10),
                Text(e.value),
              ],
            ),
          ),
      ],
    );
  }
}

class _PlaylistsView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final q = ref.watch(_libQueryProvider);
    final sort = ref.watch(_plSortProvider);
    final playlists = _sortPlaylists(
      lib.playlists
          .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
          .toList(),
      sort,
    );
    final smart = <(String, IconData, List<Track>)>[
      ('Часто слушаю', Icons.local_fire_department,
          lib.topTracks(limit: 50).map((e) => e.key).toList()),
      ('Недавнее', Icons.history, lib.history),
      ('Только лайки', Icons.favorite, lib.liked),
    ].where((s) => q.isEmpty || s.$1.toLowerCase().contains(q)).toList();
    final accent = Theme.of(context).colorScheme.primary;

    return ListView(
      children: [
        for (final s in smart)
          if (s.$3.isNotEmpty)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.18),
                child: Icon(s.$2, color: accent, size: 20),
              ),
              title: Text(s.$1,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text('${s.$3.length} треков · авто',
                  style: TextStyle(color: AppColors.white45, fontSize: 12)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TrackListScreen(title: s.$1, tracks: s.$3),
              )),
            ),
        const Divider(height: 8),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
                q.isEmpty
                    ? 'Своих плейлистов пока нет. Нажмите + или импортируйте.'
                    : 'Плейлисты не найдены.',
                style: TextStyle(color: AppColors.white45)),
          ),
        for (final pl in playlists)
          ListTile(
            leading: SizedBox(
              width: 52,
              height: 52,
              child: Artwork(pl.cover?.artworkUrl, seed: pl.id, radius: 12),
            ),
            title: Text(pl.name,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('${pl.tracks.length} треков',
                style: TextStyle(color: AppColors.white45, fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _playlistMenu(context, ref, pl),
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlaylistScreen(playlistId: pl.id),
            )),
          ),
      ],
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
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('Убрать дубликаты'),
              onTap: () async {
                Navigator.pop(context);
                final n =
                    await ref.read(libraryProvider).removeDuplicates(pl.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(n == 0
                          ? 'Дубликатов не найдено'
                          : 'Удалено дубликатов: $n')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Экспорт в файл'),
              onTap: () {
                Navigator.pop(context);
                _exportPlaylist(pl);
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

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pl = ref.watch(libraryProvider).playlists.firstWhere(
        (e) => e.id == widget.playlistId,
        orElse: () => PlaylistX(id: widget.playlistId, name: 'Плейлист'));
    final downloads = ref.watch(downloadsProvider);
    final tracks =
        pl.tracks.where((t) => _matchTrack(t, _q)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(pl.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Скачать плейлист',
            onPressed: (pl.tracks.isEmpty || downloads.playlistBusy)
                ? null
                : () => ref
                    .read(downloadsProvider)
                    .downloadPlaylist(pl.name, pl.tracks),
          ),
        ],
        bottom: downloads.playlistBusy
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                    value: downloads.playlistProgress),
              )
            : null,
      ),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: pl.tracks.isEmpty
          ? Center(
              child: Text('Плейлист пуст',
                  style: TextStyle(color: AppColors.white45)))
          : Column(
              children: [
                if (pl.tracks.length >= 8)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) =>
                          setState(() => _q = v.trim().toLowerCase()),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Поиск в плейлисте',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _q.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _q = '');
                                },
                              ),
                        filled: true,
                        fillColor: AppColors.surface2,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: tracks.isEmpty
                      ? Center(
                          child: Text('Ничего не найдено',
                              style: TextStyle(color: AppColors.white45)))
                      : ListView.builder(
                          itemCount: tracks.length,
                          itemBuilder: (_, i) {
                            final t = tracks[i];
                            return TrackRow(
                              track: t,
                              onTap: () =>
                                  playTrack(ref, context, t, queue: tracks),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TrackDownloadStatus(t),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline),
                                    tooltip: 'Убрать из плейлиста',
                                    onPressed: () => ref
                                        .read(libraryProvider)
                                        .removeFromPlaylist(
                                            widget.playlistId, t),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('Сохранить очередь как плейлист'),
              onPressed: () async {
                final name = await _askName(context, 'Новый плейлист',
                    initial: 'Очередь');
                if (name != null && name.isNotEmpty) {
                  await ref.read(libraryProvider).importPlaylist(name, queue);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'Сохранено: $name (${queue.length} треков)')));
                  }
                }
              },
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
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
          ),
        ),
      ],
    );
  }
}
