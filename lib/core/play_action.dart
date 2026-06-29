import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/models/track.dart';
import 'providers.dart';

/// Единая точка запуска трека: ставит очередь, пишет историю и открывает плеер.
void playTrack(
  WidgetRef ref,
  BuildContext context,
  Track track, {
  List<Track>? queue,
  bool openPlayer = true,
}) {
  ref.read(playbackProvider).playTrack(track, queue: queue);
  ref.read(libraryProvider).pushHistory(track);
  if (openPlayer) context.push('/player');
}
