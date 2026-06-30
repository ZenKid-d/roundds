import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/lyrics_service.dart';
import '../../domain/models/track.dart';

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

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    if (_lines.isNotEmpty) {
      final pos = ref.watch(playbackProvider).position;
      final idx = _lineFor(pos);
      if (idx != _active) {
        _active = idx;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _activeKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                alignment: 0.4, duration: const Duration(milliseconds: 300));
          }
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.track.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _body(accent),
    );
  }

  Widget _body(Color accent) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lyrics == null || _lyrics!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Текст не найден',
              style: TextStyle(color: AppColors.white45)),
        ),
      );
    }
    // Синхронизированный текст.
    if (_lines.isNotEmpty) {
      return ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
        itemCount: _lines.length,
        itemBuilder: (_, i) {
          final active = i == _active;
          return Padding(
            key: active ? _activeKey : null,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _lines[i].text.isEmpty ? '♪' : _lines[i].text,
              style: TextStyle(
                fontSize: active ? 20 : 17,
                height: 1.3,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? accent : Colors.white.withValues(alpha: 0.5),
              ),
            ),
          );
        },
      );
    }
    // Обычный текст.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      child: Text(
        _lyrics!.plain ?? '',
        style: const TextStyle(fontSize: 17, height: 1.6),
      ),
    );
  }
}
