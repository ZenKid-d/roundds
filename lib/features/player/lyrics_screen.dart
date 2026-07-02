import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/lyrics_service.dart';
import '../../domain/models/track.dart';

/// Экран текста песни в стиле Яндекс Музыки: полноэкранный, поверх размытой
/// обложки. Если есть синхронный текст (LRC) — «караоке» с плавной подсветкой
/// и авто-прокруткой по центру; иначе — обычный текст (по цепочке источников,
/// включая Genius). Открывается по умолчанию вместо обычного текста.
class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key, required this.track});
  final Track track;

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  Lyrics? _lyrics;
  List<LyricLine> _lines = [];
  bool _loading = true;
  int _active = -1;
  final _activeKey = GlobalKey();
  final _scroll = ScrollController();
  bool _translate = false;
  final Map<int, String> _tr = {}; // перевод по индексу строки

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
      _lyrics = l;
      _lines = (l?.hasSynced ?? false) ? parseLrc(l!.synced!) : [];
      _loading = false;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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

  void _centerActive() {
    final ctx = _activeKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.track.artworkUrl != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
              child: CachedNetworkImage(
                  imageUrl: widget.track.artworkUrl!, fit: BoxFit.cover),
            ),
          Container(color: Colors.black.withValues(alpha: 0.76)),
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(child: _body(accent)),
                if (!_loading &&
                    _lyrics != null &&
                    !_lyrics!.isEmpty)
                  _controls(accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() => Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          if (_lines.isNotEmpty)
            IconButton(
              tooltip: 'Перевод строки',
              icon: Icon(Icons.translate,
                  size: 20,
                  color: _translate ? Colors.white : Colors.white38),
              onPressed: () => setState(() => _translate = !_translate),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(_lines.isNotEmpty ? 'КАРАОКЕ' : 'ТЕКСТ',
                style: const TextStyle(
                    fontSize: 10.5, letterSpacing: 1.5, color: Colors.white54)),
          ),
        ],
      );

  Widget _body(Color accent) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_lyrics == null || _lyrics!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text('Текст не найден',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
        ),
      );
    }
    if (_lines.isNotEmpty) return _synced(accent);
    return _plain();
  }

  // Синхронный «караоке»: центрированные строки с плавной подсветкой.
  Widget _synced(Color accent) {
    return Consumer(builder: (context, ref, _) {
      final pos = ref.watch(positionProvider).value ??
          ref.read(playbackProvider).position;
      final idx = _lineFor(pos);
      if (idx != _active) {
        _active = idx;
        WidgetsBinding.instance.addPostFrameCallback((_) => _centerActive());
      }
      // Ленивый перевод активной строки.
      if (_translate &&
          idx >= 0 &&
          idx < _lines.length &&
          !_tr.containsKey(idx)) {
        _tr[idx] = '';
        ref
            .read(translationServiceProvider)
            .toRussian(_lines[idx].text)
            .then((t) {
          if (mounted) setState(() => _tr[idx] = t ?? '');
        });
      }
      final vpad = MediaQuery.of(context).size.height * 0.42;
      return ListView.builder(
        controller: _scroll,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(vertical: vpad, horizontal: 28),
        itemCount: _lines.length,
        itemBuilder: (_, i) {
          final active = i == idx;
          final dist = (i - idx).abs();
          final dim = active
              ? 1.0
              : dist == 1
                  ? 0.55
                  : dist == 2
                      ? 0.38
                      : 0.24;
          final translated = _tr[i];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(playbackProvider).seek(_lines[i].time),
            child: Container(
              key: active ? _activeKey : null,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    style: TextStyle(
                      fontSize: active ? 25 : 19,
                      height: 1.28,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: dim),
                    ),
                    child: Text(_lines[i].text.isEmpty ? '♪' : _lines[i].text),
                  ),
                  if (_translate &&
                      active &&
                      translated != null &&
                      translated.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        translated,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.2,
                          fontStyle: FontStyle.italic,
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  // Обычный текст (без синхронизации).
  Widget _plain() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
      child: Text(
        _lyrics!.plain ?? '',
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 18,
            height: 1.6,
            color: Colors.white.withValues(alpha: 0.85)),
      ),
    );
  }

  Widget _controls(Color accent) {
    return Consumer(builder: (context, ref, _) {
      final pc = ref.watch(playbackProvider);
      final pos = ref.watch(positionProvider).value ?? Duration.zero;
      final dur = pc.duration;
      final max = dur.inMilliseconds.toDouble();
      final value = pos.inMilliseconds.clamp(0, max <= 0 ? 1 : max).toDouble();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: max > 0 ? value : 0,
                max: max > 0 ? max : 1,
                onChanged: (v) => pc.seek(Duration(milliseconds: v.toInt())),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.skip_previous),
                    onPressed: pc.previous),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: pc.togglePlay,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: Icon(pc.isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 30, color: Colors.black),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.skip_next),
                    onPressed: pc.next),
              ],
            ),
          ],
        ),
      );
    });
  }
}
