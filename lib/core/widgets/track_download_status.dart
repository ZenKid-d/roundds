import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme/app_colors.dart';
import '../../domain/models/track.dart';

/// Индикатор состояния скачивания трека для строки списка: кружок-прогресс во
/// время загрузки, отметка «готово» для скачанного и кнопка «скачать» для
/// остального. Сам подписан на [downloadsProvider], поэтому перерисовывается
/// только эта строка, а не весь экран.
class TrackDownloadStatus extends ConsumerWidget {
  const TrackDownloadStatus(this.track, {super.key});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dl = ref.watch(downloadsProvider);
    final accent = Theme.of(context).colorScheme.primary;

    if (dl.isDownloading(track.uid)) {
      final p = dl.progressFor(track.uid);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              value: p == 0 ? null : p, strokeWidth: 2, color: accent),
        ),
      );
    }
    if (dl.isDownloaded(track.uid)) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(Icons.download_done, size: 20, color: accent),
      );
    }
    return IconButton(
      icon: Icon(Icons.download_outlined, color: AppColors.white45),
      tooltip: 'Скачать трек',
      onPressed: () => ref.read(downloadsProvider).download(track),
    );
  }
}
