import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'playlist_actions.dart' show showAddToPlaylistSheet;
import 'providers.dart';
import 'share_card.dart';
import 'theme/app_colors.dart';
import 'widgets/artwork.dart';
import '../domain/models/track.dart';
import '../features/album/album_screen.dart';

/// Контекстное меню трека (по долгому тапу): играть следующим / в очередь /
/// радио / скачать / в плейлист / избранное.
Future<void> showTrackMenu(
    BuildContext context, WidgetRef ref, Track track) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface1,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Artwork(track.artworkUrl,
                size: 44, seed: track.uid, radius: 10),
            title: Text(track.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.white45)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.playlist_play),
            title: const Text('Играть следующим'),
            onTap: () {
              ref.read(playbackProvider).playNext(track);
              ref.read(recsStoreProvider).recordRepeat(track);
              Navigator.pop(sheetCtx);
              _snack(context, 'Играет следующим');
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('Добавить в очередь'),
            onTap: () {
              ref.read(playbackProvider).addToQueue(track);
              ref.read(recsStoreProvider).recordRepeat(track);
              Navigator.pop(sheetCtx);
              _snack(context, 'Добавлено в очередь');
            },
          ),
          ListTile(
            leading: const Icon(Icons.radio),
            title: const Text('Радио по треку'),
            onTap: () async {
              Navigator.pop(sheetCtx);
              _snack(context, 'Собираю радио…');
              final list = await ref
                  .read(recommendationServiceProvider)
                  .radioFrom(track);
              await ref.read(playbackProvider).startRadio(track, list);
              ref.read(libraryProvider).pushHistory(track);
              if (context.mounted) context.push('/player');
            },
          ),
          Consumer(builder: (_, r, __) {
            final done = r.watch(downloadsProvider).isDownloaded(track.uid);
            return ListTile(
              leading: Icon(done ? Icons.download_done : Icons.download),
              title: Text(done ? 'Уже скачано' : 'Скачать'),
              enabled: !done,
              onTap: () {
                r.read(downloadsProvider).download(track);
                Navigator.pop(sheetCtx);
                _snack(context, 'Скачивание…');
              },
            );
          }),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Добавить в плейлист'),
            onTap: () {
              Navigator.pop(sheetCtx);
              showAddToPlaylistSheet(context, ref, track);
            },
          ),
          Consumer(builder: (_, r, __) {
            final liked = r.watch(libraryProvider).isLiked(track);
            return ListTile(
              leading: Icon(liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? AppColors.danger : null),
              title: Text(liked ? 'Убрать из избранного' : 'В избранное'),
              onTap: () {
                r.read(libraryProvider).toggleLike(track);
                Navigator.pop(sheetCtx);
              },
            );
          }),
          Consumer(builder: (_, r, __) {
            final disliked = r.watch(recsStoreProvider).isDisliked(track);
            return ListTile(
              leading: Icon(
                  disliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                  color: disliked ? AppColors.warning : null),
              title: Text(disliked ? 'Убрать дизлайк' : 'Не нравится'),
              subtitle: disliked
                  ? null
                  : Text('Больше не показывать в рекомендациях',
                      style:
                          TextStyle(color: AppColors.white45, fontSize: 11)),
              onTap: () {
                r.read(recsStoreProvider).toggleDislike(track);
                Navigator.pop(sheetCtx);
              },
            );
          }),
          if ((track.album ?? '').isNotEmpty)
            ListTile(
              leading: const Icon(Icons.album),
              title: const Text('Открыть альбом'),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AlbumScreen(seed: track)));
              },
            ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Поделиться карточкой'),
            onTap: () {
              Navigator.pop(sheetCtx);
              shareTrackCard(context, ref, track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, size: 22),
            title: Text('Скрыть артиста «${track.artist}»'),
            onTap: () {
              ref.read(libraryProvider).blacklistArtist(track.artist);
              Navigator.pop(sheetCtx);
              _snack(context, '«${track.artist}» скрыт из ленты и радио');
            },
          ),
        ],
      ),
    ),
  );
}

void _snack(BuildContext c, String m) {
  if (c.mounted) {
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
  }
}
