import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/mini_player.dart';
import '../../core/widgets/service_badge.dart';
import '../../core/widgets/track_card.dart';
import '../../domain/models/source_type.dart';
import '../../domain/models/track.dart';

class ChartsScreen extends ConsumerWidget {
  const ChartsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final sources =
        SourceType.values.where((s) => settings.isEnabled(s)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Новинки и чарты')),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          for (final s in sources) _SourceCharts(source: s),
          if (sources.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Включите источники в Настройках.',
                  style: TextStyle(color: AppColors.white45)),
            ),
        ],
      ),
    );
  }
}

class _SourceCharts extends ConsumerWidget {
  const _SourceCharts({required this.source});
  final SourceType source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Track>>(
      future: ref.read(aggregatorProvider).sourceFor(source).feed(limit: 20),
      builder: (context, snap) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Row(
                children: [
                  ServiceBadge(source, size: 22),
                  const SizedBox(width: 8),
                  Text('Чарт · ${source.shortLabel}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            SizedBox(
              height: 172,
              child: snap.connectionState != ConnectionState.done
                  ? const Center(child: CircularProgressIndicator())
                  : (snap.data == null || snap.data!.isEmpty)
                      ? Center(
                          child: Text('Недоступно',
                              style: TextStyle(color: AppColors.white45)))
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: snap.data!.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (_, i) => SizedBox(
                            width: 132,
                            child: TrackCard(
                              track: snap.data![i],
                              onTap: () => playTrack(
                                  ref, context, snap.data![i],
                                  queue: snap.data!),
                            ),
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}
