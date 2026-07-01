import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/mini_player.dart';
import '../../core/widgets/track_card.dart';
import '../../domain/models/track.dart';

/// Универсальный экран со списком треков: статический список или загрузчик.
/// Кнопки «Слушать всё» и «Радио», мини-плеер внизу.
class TrackListScreen extends ConsumerStatefulWidget {
  const TrackListScreen({
    super.key,
    required this.title,
    this.tracks,
    this.loader,
  });

  final String title;
  final List<Track>? tracks;
  final Future<List<Track>> Function()? loader;

  @override
  ConsumerState<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends ConsumerState<TrackListScreen> {
  List<Track>? _tracks;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.tracks != null) {
      _tracks = widget.tracks;
    } else if (widget.loader != null) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final t = await widget.loader!();
      if (mounted) setState(() => _tracks = t);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final tracks = _tracks;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Ошибка: $_error',
                        style: TextStyle(color: AppColors.white45)),
                  ),
                )
              : (tracks == null || tracks.isEmpty)
                  ? Center(
                      child: Text('Пусто',
                          style: TextStyle(color: AppColors.white45)))
                  : Column(
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => playTrack(
                                      ref, context, tracks.first,
                                      queue: tracks),
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Слушать всё'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: () => ref
                                    .read(playbackProvider)
                                    .startRadio(tracks.first, tracks),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: accent),
                                icon: const Icon(Icons.radio),
                                label: const Text('Радио'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: tracks.length,
                            itemBuilder: (_, i) => TrackRow(
                              track: tracks[i],
                              onTap: () => playTrack(ref, context, tracks[i],
                                  queue: tracks),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
