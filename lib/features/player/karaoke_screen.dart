import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/lyrics_service.dart';
import '../../domain/models/track.dart';

/// Полноэкранный караоке-режим: крупная текущая строка синхронного текста
/// поверх размытой обложки. Текст загружается из lrclib в рантайме.
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
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final idx = _synced ? _lineFor(pos) : -1;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Expanded(child: _body(accent, idx)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(Color accent, int idx) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
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
    // Окно строк вокруг текущей.
    return Center(
      child: Padding(
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
  }
}
