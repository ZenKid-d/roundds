import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/service_badge.dart';
import '../../core/widgets/track_card.dart';
import '../../core/widgets/vinyl_disc.dart';
import '../../domain/models/track.dart';
import '../../playback/audio_handler.dart';
import 'lyrics_screen.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pc = ref.watch(playbackProvider);
    final accent = Theme.of(context).colorScheme.primary;
    final track = pc.current;

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Ничего не играет')),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.7),
            radius: 1.1,
            colors: [accent.withValues(alpha: 0.28), Colors.black],
            stops: const [0, 0.7],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              children: [
                _topBar(context, track),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: VinylDisc(
                      artworkUrl: track.artworkUrl,
                      isPlaying: pc.isPlaying,
                      accent: accent,
                      seed: track.uid,
                      size: 250,
                    ),
                  ),
                ),
                Text(track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: AppColors.white45)),
                const SizedBox(height: 11),
                ServicePill(track.source),
                if (pc.error != null) _errorBox(context, ref, track, pc.error!),
                const SizedBox(height: 14),
                _progress(context, ref, pc.position, pc.duration),
                _controls(context, ref, pc.isPlaying, pc.isLoading),
                const SizedBox(height: 14),
                _tools(context, ref, track),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, Track track) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => context.pop(),
        ),
        const Expanded(
          child: Text('СЕЙЧАС ИГРАЕТ',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10.5, letterSpacing: 1.5, color: Colors.white54)),
        ),
        IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
      ],
    );
  }

  Widget _progress(
      BuildContext context, WidgetRef ref, Duration pos, Duration dur) {
    final max = dur.inMilliseconds.toDouble();
    final value = pos.inMilliseconds.clamp(0, max).toDouble();
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: max > 0 ? value : 0,
            max: max > 0 ? max : 1,
            onChanged: (v) =>
                ref.read(playbackProvider).seek(Duration(milliseconds: v.toInt())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(pos),
                  style: TextStyle(fontSize: 10.5, color: AppColors.white45)),
              Text(_fmt(dur),
                  style: TextStyle(fontSize: 10.5, color: AppColors.white45)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controls(
      BuildContext context, WidgetRef ref, bool playing, bool loading) {
    final accent = Theme.of(context).colorScheme.primary;
    final pc = ref.read(playbackProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
              icon: Icon(Icons.shuffle,
                  color: pc.isShuffle ? accent : AppColors.white45),
              onPressed: pc.toggleShuffle),
          const SizedBox(width: 10),
          IconButton(
              iconSize: 38,
              icon: const Icon(Icons.skip_previous),
              onPressed: pc.previous),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: pc.togglePlay,
            child: Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Icon(playing ? Icons.pause : Icons.play_arrow,
                      size: 34, color: Colors.black),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
              iconSize: 38,
              icon: const Icon(Icons.skip_next),
              onPressed: pc.next),
          const SizedBox(width: 10),
          IconButton(
              icon: Icon(
                  pc.repeatMode == LoopMode.one
                      ? Icons.repeat_one
                      : Icons.repeat,
                  color: pc.repeatMode == LoopMode.off
                      ? AppColors.white45
                      : accent),
              onPressed: pc.cycleRepeat),
        ],
      ),
    );
  }

  Widget _tools(BuildContext context, WidgetRef ref, Track track) {
    final accent = Theme.of(context).colorScheme.primary;
    final liked = ref.watch(libraryProvider).isLiked(track);
    final downloads = ref.watch(downloadsProvider);
    final downloaded = downloads.isDownloaded(track.uid);
    final downloading = downloads.isDownloading(track.uid);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        IconButton(
            icon: Icon(Icons.lyrics_outlined, color: AppColors.white60),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => LyricsScreen(track: track),
                ))),
        IconButton(
            icon: Icon(Icons.queue_music, color: AppColors.white60),
            onPressed: () => _showQueue(context, ref)),
        IconButton(
            icon: downloading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: accent))
                : Icon(
                    downloaded
                        ? Icons.download_done
                        : Icons.download_outlined,
                    color: downloaded ? accent : AppColors.white60),
            onPressed: () {
              if (downloaded) {
                ref.read(downloadsProvider).remove(track.uid);
              } else if (!downloading) {
                ref.read(downloadsProvider).download(track);
              }
            }),
        IconButton(
            icon: Icon(Icons.add_circle_outline, color: AppColors.white60),
            onPressed: () => _addToPlaylist(context, ref, track)),
        IconButton(
            icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                color: liked ? accent : AppColors.white60),
            onPressed: () => ref.read(libraryProvider).toggleLike(track)),
      ],
    );
  }

  void _showQueue(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface1,
      isScrollControlled: true,
      builder: (_) {
        final pc = ref.read(playbackProvider);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (_, scroll) => ListView(
            controller: scroll,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Очередь',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ),
              for (final t in pc.queue)
                TrackRow(
                  track: t,
                  active: t.uid == pc.current?.uid,
                  onTap: () {
                    pc.playTrack(t, queue: pc.queue);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _addToPlaylist(BuildContext context, WidgetRef ref, Track track) {
    final lib = ref.read(libraryProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface1,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Добавить в плейлист',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ),
            if (lib.playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Сначала создайте плейлист в Медиатеке.',
                    style: TextStyle(color: AppColors.white45)),
              ),
            for (final pl in lib.playlists)
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: Text(pl.name),
                onTap: () {
                  lib.addToPlaylist(pl.id, track);
                  Navigator.pop(context);
                  _todo(context, 'Добавлено в «${pl.name}»');
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(
      BuildContext context, WidgetRef ref, Track track, String error) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFE24B4A).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: const Color(0xFFE24B4A).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                color: Color(0xFFE24B4A), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(error,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => ref.read(playbackProvider).playTrack(track),
              child: const Text('Повтор'),
            ),
          ],
        ),
      ),
    );
  }

  void _todo(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
