import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/track_card.dart';
import '../../domain/models/track.dart';

/// Лента главного экрана — микс из всех включённых источников.
final feedProvider = FutureProvider<List<Track>>((ref) async {
  ref.watch(settingsProvider); // пере-загрузка при смене набора источников
  return ref.read(aggregatorProvider).feed();
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(libraryProvider).history;
    final feed = ref.watch(feedProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(feedProvider.future),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _Greeting()),
          if (history.isNotEmpty) ...[
            const _SectionHeader('Продолжить слушать'),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 172,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => SizedBox(
                    width: 132,
                    child: TrackCard(
                      track: history[i],
                      onTap: () => playTrack(ref, context, history[i],
                          queue: history),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const _SectionHeader('Со всех сервисов'),
          feed.when(
            loading: () => const SliverToBoxAdapter(child: _Loading()),
            error: (e, _) => SliverToBoxAdapter(child: _Error('$e')),
            data: (tracks) {
              if (tracks.isEmpty) {
                return const SliverToBoxAdapter(
                  child: _Empty('Пусто. Включите источники в Настройках.'),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => TrackCard(
                      track: tracks[i],
                      onTap: () =>
                          playTrack(ref, context, tracks[i], queue: tracks),
                    ),
                    childCount: tracks.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Добрый вечер',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('Всё, что ты слушаешь — в одном месте',
              style: TextStyle(fontSize: 12, color: AppColors.white45)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
        child: Text(title,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _Error extends StatelessWidget {
  const _Error(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Не удалось загрузить ленту.\n$message',
            style: TextStyle(color: AppColors.white45, fontSize: 12)),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message,
            style: TextStyle(color: AppColors.white45, fontSize: 13)),
      );
}
