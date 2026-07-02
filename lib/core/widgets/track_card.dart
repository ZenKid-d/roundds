import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/track.dart';
import '../theme/app_colors.dart';
import '../track_menu.dart';
import 'artwork.dart';
import 'service_badge.dart';

/// Вертикальная карточка трека (для рядов и грида на главной/в поиске).
class TrackCard extends StatefulWidget {
  const TrackCard({
    super.key,
    required this.track,
    required this.onTap,
    this.width = double.infinity,
    this.coverSize,
  });

  final Track track;
  final VoidCallback onTap;
  final double width;
  final double? coverSize;

  @override
  State<TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<TrackCard> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapCancel: () => setState(() => _scale = 1),
      onTapUp: (_) => setState(() => _scale = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Artwork(t.artworkUrl, seed: t.uid),
                    Positioned(
                      left: 7,
                      bottom: 7,
                      child: ServiceBadge(t.source),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(
                t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
              Text(
                t.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: AppColors.white45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Горизонтальная строка трека (для поиска, плейлистов, очереди).
/// По долгому тапу — контекстное меню (играть следующим / в очередь / радио…).
class TrackRow extends ConsumerWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.onTap,
    this.trailing,
    this.active = false,
    this.onLongPress,
  });

  final Track track;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool active;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      onTap: onTap,
      onLongPress:
          onLongPress ?? () => showTrackMenu(context, ref, track),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Artwork(track.artworkUrl, seed: track.uid, radius: 12),
            Positioned(
              right: -2,
              bottom: -2,
              child: ServiceBadge(track.source, size: 16),
            ),
          ],
        ),
      ),
      title: Text(track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: active
                ? Theme.of(context).colorScheme.primary
                : Colors.white,
          )),
      subtitle: Text(track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: AppColors.white45)),
      trailing: trailing,
    );
  }
}
