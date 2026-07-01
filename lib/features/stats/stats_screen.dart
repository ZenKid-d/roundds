import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/track_card.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final tracks = lib.topTracks(limit: 30);
    final artists = lib.topArtists(limit: 12);
    final accent = Theme.of(context).colorScheme.primary;

    if (tracks.isEmpty && lib.totalListened == Duration.zero) {
      return Scaffold(
        appBar: AppBar(title: const Text('Статистика')),
        body: Center(
          child: Text('Пока нет прослушиваний',
              style: TextStyle(color: AppColors.white45)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.1,
              children: [
                _Metric('Всего прослушано', _fmtDur(lib.totalListened),
                    accent: accent, big: true),
                _Metric('Прослушиваний', '${lib.totalPlays}'),
                _Metric('Уникальных треков', '${lib.uniqueTracks}'),
                _Metric('Артистов', '${lib.uniqueArtists}'),
              ],
            ),
          ),
          if (artists.isNotEmpty) ...[
            _header('Топ артистов'),
            for (var i = 0; i < artists.length; i++)
              ListTile(
                leading: Text('${i + 1}',
                    style: TextStyle(color: AppColors.white45)),
                title: Text(artists[i].key,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text('${artists[i].value}',
                    style: TextStyle(color: accent)),
              ),
          ],
          _header('Топ треков'),
          for (final e in tracks)
            TrackRow(
              track: e.key,
              onTap: () => playTrack(ref, context, e.key,
                  queue: tracks.map((x) => x.key).toList()),
              trailing: Text('${e.value}',
                  style: TextStyle(color: accent, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Text(t,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      );
}

String _fmtDur(Duration d) {
  final days = d.inDays;
  final hours = d.inHours % 24;
  final mins = d.inMinutes % 60;
  if (days > 0) return '$days д $hours ч';
  if (d.inHours > 0) return '${d.inHours} ч $mins мин';
  if (d.inMinutes > 0) return '$mins мин';
  return '${d.inSeconds} сек';
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.accent, this.big = false});
  final String label;
  final String value;
  final Color? accent;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11.5, color: AppColors.white45)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: big ? 22 : 20,
                fontWeight: FontWeight.w600,
                color: big ? (accent ?? Colors.white) : Colors.white,
              )),
        ],
      ),
    );
  }
}
