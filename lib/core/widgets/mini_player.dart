import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';
import '../theme/app_colors.dart';
import '../theme/theme_settings.dart';
import 'artwork.dart';

/// Закреплённый мини-плеер. Показывается, когда есть текущий трек.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pc = ref.watch(playbackProvider);
    final track = pc.current;
    if (track == null) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.primary;
    final showEq = ref.watch(themeSettingsProvider).animLevel != AnimLevel.min;

    return GestureDetector(
      onTap: () => context.push('/player'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface2.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.white06),
        ),
        child: Row(
          children: [
            Artwork(track.artworkUrl, size: 44, seed: track.uid, radius: 12),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w500)),
                  Text(track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 10.5, color: AppColors.white45)),
                ],
              ),
            ),
            if (pc.isPlaying && showEq) _Equalizer(color: accent),
            const SizedBox(width: 8),
            _RoundIcon(
              icon: pc.isLoading
                  ? Icons.hourglass_empty
                  : (pc.isPlaying ? Icons.pause : Icons.play_arrow),
              color: accent,
              onTap: pc.togglePlay,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(
      {required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: Colors.black),
      ),
    );
  }
}

class _Equalizer extends StatefulWidget {
  const _Equalizer({required this.color});
  final Color color;

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(4, (i) {
              final phase = (_c.value + i * 0.22) % 1.0;
              final h = 4 + (10 * (0.5 - (phase - 0.5).abs()) * 2);
              return Container(
                width: 2.5,
                height: h,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
