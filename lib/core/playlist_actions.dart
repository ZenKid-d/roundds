import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/track.dart';
import 'providers.dart';
import 'theme/app_colors.dart';

/// Общий bottom-sheet «Добавить в плейлист». Раньше та же логика была
/// продублирована в [showTrackMenu] (lib/core/track_menu.dart) и на экране
/// плеера (lib/features/player/now_playing_screen.dart) — с небольшими
/// расхождениями (один умел создавать плейлист, другой показывал пустое
/// состояние). Здесь — единая полная версия.
///
/// Показывает список существующих плейлистов + пункт «Новый плейлист»,
/// после выбора показывает снек и закрывает шторку.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final lib = ref.read(libraryProvider);
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface1,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Добавить в плейлист',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Новый плейлист'),
            onTap: () async {
              Navigator.pop(sheetCtx);
              final name = await _askPlaylistName(context);
              if (name == null || name.isEmpty) return;
              final pl = await lib.createPlaylist(name);
              await lib.addToPlaylist(pl.id, track);
              if (context.mounted) {
                _snack(context, 'Добавлено в «$name»');
              }
            },
          ),
          if (lib.playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Плейлистов пока нет — создайте первый.',
                style: TextStyle(color: AppColors.white45),
              ),
            ),
          for (final pl in lib.playlists)
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(pl.name),
              subtitle: Text('${pl.tracks.length} треков',
                  style: TextStyle(color: AppColors.white45, fontSize: 12)),
              onTap: () {
                lib.addToPlaylist(pl.id, track);
                Navigator.pop(sheetCtx);
                _snack(context, 'Добавлено в «${pl.name}»');
              },
            ),
        ],
      ),
    ),
  );
}

Future<String?> _askPlaylistName(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface2,
      title: const Text('Новый плейлист'),
      content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Название')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.pop(context, c.text.trim()),
          child: const Text('Создать'),
        ),
      ],
    ),
  );
}

void _snack(BuildContext context, String message) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
