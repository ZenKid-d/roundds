import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_settings.dart';
import '../../core/widgets/animated_bg.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/player_visualizer.dart';
import '../../core/widgets/service_badge.dart';
import '../../core/widgets/track_card.dart';
import '../../core/widgets/vinyl_disc.dart';
import '../../domain/models/track.dart';
import '../../playback/audio_handler.dart';
import '../artist/artist_screen.dart';
import '../common/track_list_screen.dart';
import 'equalizer_screen.dart';
import 'lyrics_screen.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  int _dir = 1; // направление смены пластинки: 1 — вперёд, -1 — назад

  void _goNext() {
    setState(() => _dir = 1);
    ref.read(playbackProvider).next();
  }

  void _goPrev() {
    setState(() => _dir = -1);
    ref.read(playbackProvider).previous();
  }

  @override
  Widget build(BuildContext context) {
    final pc = ref.watch(playbackProvider);
    final accent = Theme.of(context).colorScheme.primary;
    final ts = ref.watch(themeSettingsProvider);
    final track = pc.current;

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Ничего не играет')),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedPlayerBg(
              accent: accent, animate: ts.animLevel != AnimLevel.min),
          SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              children: [
                _topBar(context, ref, track),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      // Жесты: свайп влево — след., вправо — пред., вниз — закрыть.
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v < -250) {
                          _goNext();
                        } else if (v > 250) {
                          _goPrev();
                        }
                      },
                      onVerticalDragEnd: (d) {
                        if ((d.primaryVelocity ?? 0) > 300) context.pop();
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) {
                          // «Подъём иглы»: старая пластинка приподнимается и
                          // уходит вверх, новая поднимается снизу. Без поворота.
                          final incoming = child.key == ValueKey(track.uid);
                          final dir = incoming ? _dir : -_dir;
                          final slide = Tween<Offset>(
                            begin: Offset(0, 0.5 * dir),
                            end: Offset.zero,
                          ).animate(anim);
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: slide,
                              child: ScaleTransition(
                                scale:
                                    Tween(begin: 0.92, end: 1.0).animate(anim),
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(track.uid),
                          child: ts.playerView == PlayerView.cover
                              ? _coverArt(track, accent)
                              : VinylDisc(
                                  artworkUrl: track.artworkUrl,
                                  isPlaying: pc.isPlaying && ts.spin,
                                  accent: accent,
                                  seed: track.uid,
                                  size: 250,
                                ),
                        ),
                      ),
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
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ArtistScreen(artist: track.artist),
                  )),
                  child: Text(track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13, color: AppColors.white45)),
                ),
                const SizedBox(height: 11),
                ServicePill(track.source),
                if (pc.error != null) _errorBox(context, ref, track, pc.error!),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: PlayerVisualizer(
                      playing: pc.isPlaying, color: accent, height: 26),
                ),
                const SizedBox(height: 8),
                _progress(context, ref, pc.duration),
                _controls(context, ref, pc.isPlaying, pc.isLoading),
                const SizedBox(height: 14),
                _tools(context, ref, track),
                const SizedBox(height: 10),
              ],
            ),
          ),
          ),
        ],
      ),
    );
  }

  Widget _coverArt(Track track, Color accent) {
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 50,
              spreadRadius: 2),
        ],
      ),
      child: Artwork(track.artworkUrl, size: 280, radius: 24, seed: track.uid),
    );
  }

  Widget _topBar(BuildContext context, WidgetRef ref, Track track) {
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
        IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () => _moreMenu(context, ref, track)),
      ],
    );
  }

  Widget _progress(BuildContext context, WidgetRef ref, Duration dur) {
    final max = dur.inMilliseconds.toDouble();
    // Отдельный Consumer на позиции — тикает только он, не весь плеер.
    return Consumer(
      builder: (context, ref, _) {
        final pos = ref.watch(positionProvider).value ?? Duration.zero;
        final value =
            pos.inMilliseconds.clamp(0, max <= 0 ? 1 : max).toDouble();
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                value: max > 0 ? value : 0,
                max: max > 0 ? max : 1,
                onChanged: (v) => ref
                    .read(playbackProvider)
                    .seek(Duration(milliseconds: v.toInt())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(pos),
                      style:
                          TextStyle(fontSize: 10.5, color: AppColors.white45)),
                  Text(_fmt(dur),
                      style:
                          TextStyle(fontSize: 10.5, color: AppColors.white45)),
                ],
              ),
            ),
          ],
        );
      },
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
              onPressed: _goPrev),
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
              onPressed: _goNext),
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
                        value: downloads.progressFor(track.uid) == 0
                            ? null
                            : downloads.progressFor(track.uid),
                        strokeWidth: 2,
                        color: accent))
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

  void _moreMenu(BuildContext context, WidgetRef ref, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface1,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.radio),
              title: const Text('Радио по этому треку'),
              onTap: () async {
                Navigator.pop(context);
                final list = await ref
                    .read(recommendationServiceProvider)
                    .radioFrom(track);
                await ref.read(playbackProvider).startRadio(track, list);
              },
            ),
            ListTile(
              leading: const Icon(Icons.recommend_outlined),
              title: const Text('Похожие треки'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TrackListScreen(
                    title: 'Похоже на «${track.title}»',
                    loader: () => ref
                        .read(recommendationServiceProvider)
                        .similarTo(track),
                  ),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('Скорость воспроизведения'),
              onTap: () {
                Navigator.pop(context);
                _speedSheet(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.equalizer),
              title: const Text('Эквалайзер'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const EqualizerScreen()));
              },
            ),
            Consumer(builder: (context, ref, _) {
              final timer = ref.watch(sleepTimerProvider);
              final rem = timer.remaining;
              final afterTrack = ref.watch(playbackProvider).sleepAfterTrack;
              final active = timer.active || afterTrack;
              final subtitle = afterTrack
                  ? 'До конца трека'
                  : (rem != null ? 'Осталось ${_fmt(rem)}' : null);
              return ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('Таймер сна'),
                subtitle: subtitle != null ? Text(subtitle) : null,
                trailing: active
                    ? TextButton(
                        onPressed: () {
                          ref.read(sleepTimerProvider).cancel();
                          ref.read(playbackProvider)
                            ..setSleepAfterTrack(false)
                            ..setVolume(1);
                        },
                        child: const Text('Стоп'))
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _sleepSheet(context, ref);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _sleepSheet(BuildContext context, WidgetRef ref) {
    const options = {'15 минут': 15, '30 минут': 30, '45 минут': 45, '1 час': 60};
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface1,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Уснуть через',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ),
            ListTile(
              leading: const Icon(Icons.music_note),
              title: const Text('До конца текущего трека'),
              onTap: () {
                ref.read(sleepTimerProvider).cancel();
                ref.read(playbackProvider).setSleepAfterTrack(true);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Пауза после текущего трека')));
              },
            ),
            for (final e in options.entries)
              ListTile(
                title: Text(e.key),
                subtitle: const Text('С плавным затуханием в конце',
                    style: TextStyle(fontSize: 11)),
                onTap: () {
                  final pc = ref.read(playbackProvider);
                  pc.setSleepAfterTrack(false);
                  const fadeMs = 30000; // затухание в последние 30 сек
                  ref.read(sleepTimerProvider).start(
                    Duration(minutes: e.value),
                    () {
                      pc.pause();
                      pc.setVolume(1); // вернуть громкость для след. запуска
                    },
                    onTick: (rem) {
                      final v = rem.inMilliseconds >= fadeMs
                          ? 1.0
                          : (rem.inMilliseconds / fadeMs).clamp(0.0, 1.0);
                      pc.setVolume(v);
                    },
                  );
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Таймер сна: ${e.key}')));
                },
              ),
          ],
        ),
      ),
    );
  }

  void _speedSheet(BuildContext context, WidgetRef ref) {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final current = ref.read(playbackProvider).speed;
    final accent = Theme.of(context).colorScheme.primary;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface1,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Скорость',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ),
            for (final s in speeds)
              ListTile(
                title: Text('${s}x'),
                trailing: (s - current).abs() < 0.01
                    ? Icon(Icons.check, color: accent)
                    : null,
                onTap: () {
                  ref.read(playbackProvider).setSpeed(s);
                  Navigator.pop(context);
                },
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
