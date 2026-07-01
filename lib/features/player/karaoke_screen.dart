import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/lyrics_service.dart';
import '../../domain/models/track.dart';

/// Полноэкранный караоке-режим: крупная текущая строка синхронного текста
/// поверх размытой обложки, с анимацией смены строк, прогресс-баром и
/// кнопками переключения. Текст загружается из lrclib в рантайме.
class KaraokeScreen extends ConsumerStatefulWidget {
  const KaraokeScreen({super.key, required this.track});
  final Track track;

  @override
  ConsumerState<KaraokeScreen> createState() => _KaraokeScreenState();
}

class _KaraokeScreenState extends ConsumerState<KaraokeScreen> {
  List<LyricLine> _lines = [];
  bool _loading = true;
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final l = await ref.read(lyricsServiceProvider).fetch(
          artist: widget.track.artist,
          title: widget.track.title,
          duration: widget.track.duration,
        );
    if (!mounted) return;
    setState(() {
      _synced = l?.hasSynced ?? false;
      _lines = _synced ? parseLrc(l!.synced!) : const [];
      _loading = false;
    });
  }

  int _lineFor(Duration pos) {
    var idx = -1;
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].time <= pos) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Фон статичен — не перестраивается на каждый тик позиции.
          if (widget.track.artworkUrl != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: CachedNetworkImage(
                  imageUrl: widget.track.artworkUrl!, fit: BoxFit.cover),
            ),
          Container(color: Colors.black.withValues(alpha: 0.72)),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Text('КАРАОКЕ',
                          style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: 1.5,
                              color: Colors.white54)),
                    ),
                  ],
                ),
                Expanded(child: _lyrics(accent)),
                _controls(accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lyrics(Color accent) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_synced) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text('Синхронного текста нет для этого трека',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
        ),
      );
    }
    // Только эта часть перестраивается на тик позиции.
    return Consumer(builder: (context, ref, _) {
      final pos = ref.watch(positionProvider).value ?? Duration.zero;
      final idx = _lineFor(pos);
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.14), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: Padding(
          key: ValueKey(idx),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = idx - 2; i <= idx + 3; i++)
                if (i >= 0 && i < _lines.length)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _lines[i].text.isEmpty ? '♪' : _lines[i].text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: i == idx ? 26 : 18,
                        height: 1.25,
                        fontWeight:
                            i == idx ? FontWeight.w700 : FontWeight.w400,
                        color: i == idx
                            ? accent
                            : Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      );
    });
  }

  Widget _controls(Color accent) {
    return Consumer(builder: (context, ref, _) {
      final pc = ref.watch(playbackProvider);
      final pos = ref.watch(positionProvider).value ?? Duration.zero;
      final dur = pc.duration;
      final max = dur.inMilliseconds.toDouble();
      final value = pos.inMilliseconds.clamp(0, max <= 0 ? 1 : max).toDouble();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              value: max > 0 ? value : 0,
              max: max > 0 ? max : 1,
              onChanged: (v) =>
                  pc.seek(Duration(milliseconds: v.toInt())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(pos),
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.white54)),
                  Text(_fmt(dur),
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.white54)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    iconSize: 34,
                    icon: const Icon(Icons.skip_previous),
                    onPressed: pc.previous),
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: pc.togglePlay,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: Icon(pc.isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 30, color: Colors.black),
                  ),
                ),
                const SizedBox(width: 14),
                IconButton(
                    iconSize: 34,
                    icon: const Icon(Icons.skip_next),
                    onPressed: pc.next),
              ],
            ),
          ],
        ),
      );
    });
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
