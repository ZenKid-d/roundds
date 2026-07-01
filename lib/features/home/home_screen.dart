import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/track_card.dart';
import '../../data/recommendation_service.dart';
import '../../domain/models/track.dart';
import '../charts/charts_screen.dart';

/// Лента главного экрана — микс из всех включённых источников.
final feedProvider = FutureProvider<List<Track>>((ref) async {
  ref.watch(settingsProvider);
  return ref.read(aggregatorProvider).feed();
});

/// Персональные рекомендации (на основе истории/лайков/статистики).
/// Читаем библиотеку через read (не watch), чтобы не пересчитывать на каждый трек.
final recommendationsProvider = FutureProvider<List<RecoRow>>((ref) async {
  ref.watch(settingsProvider);
  final lib = ref.read(libraryProvider);
  if (lib.history.isEmpty && lib.liked.isEmpty) return const [];
  return ref.read(recommendationServiceProvider).forYou(
        history: lib.history,
        liked: lib.liked,
        topTracks: lib.topTracks(limit: 10),
        topArtists: lib.topArtists(limit: 5),
      );
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final history = lib.history;
    final feed = ref.watch(feedProvider);
    final recos = ref.watch(recommendationsProvider).value ?? const <RecoRow>[];
    final canRadio = history.isNotEmpty || lib.liked.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(recommendationsProvider);
        ref.invalidate(feedProvider);
        await ref.read(feedProvider.future);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _Greeting()),
          if (canRadio)
            SliverToBoxAdapter(
              child: _RadioCard(onTap: () => _startTasteRadio(ref, context)),
            ),
          SliverToBoxAdapter(
            child: _GenreChips(
                onGenre: (g) => _startGenreRadio(ref, context, g)),
          ),
          SliverToBoxAdapter(
            child: ListTile(
              leading:
                  Icon(Icons.trending_up, color: AppColors.white60),
              title: const Text('Новинки и чарты'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChartsScreen())),
            ),
          ),
          if (history.isNotEmpty) ...[
            const _SectionHeader('Продолжить слушать'),
            SliverToBoxAdapter(child: _trackHRow(ref, context, history)),
          ],
          for (final row in recos) ...[
            _SectionHeader(row.title),
            SliverToBoxAdapter(child: _trackHRow(ref, context, row.tracks)),
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

Widget _trackHRow(WidgetRef ref, BuildContext context, List<Track> tracks) {
  return SizedBox(
    height: 172,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (_, i) => SizedBox(
        width: 132,
        child: TrackCard(
          track: tracks[i],
          onTap: () => playTrack(ref, context, tracks[i], queue: tracks),
        ),
      ),
    ),
  );
}

Future<void> _startGenreRadio(
    WidgetRef ref, BuildContext context, String genre) async {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Радио: $genre'), duration: const Duration(seconds: 1)));
  final results = await ref.read(aggregatorProvider).search(genre, perSource: 15);
  if (results.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ничего не найдено')));
    }
    return;
  }
  await ref.read(playbackProvider).startRadio(results.first, results);
  ref.read(libraryProvider).pushHistory(results.first);
  if (context.mounted) context.push('/player');
}

class _GenreChips extends StatelessWidget {
  const _GenreChips({required this.onGenre});
  final void Function(String genre) onGenre;

  static const _genres = [
    'Поп', 'Рок', 'Хип-хоп', 'Электроника', 'Инди', 'Джаз', 'Классика', 'Метал',
  ];

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        itemCount: _genres.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => onGenre(_genres[i]),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Text(_genres[i],
                style: const TextStyle(fontSize: 12.5, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

Future<void> _startTasteRadio(WidgetRef ref, BuildContext context) async {
  final lib = ref.read(libraryProvider);
  final seed = lib.history.isNotEmpty
      ? lib.history.first
      : (lib.liked.isNotEmpty ? lib.liked.first : null);
  if (seed == null) return;
  ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Собираю радио…'), duration: Duration(seconds: 1)));
  final list = await ref.read(recommendationServiceProvider).radioFrom(seed);
  await ref.read(playbackProvider).startRadio(seed, list);
  ref.read(libraryProvider).pushHistory(seed);
  if (context.mounted) context.push('/player');
}

class _RadioCard extends StatelessWidget {
  const _RadioCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                child: const Icon(Icons.radio, color: Colors.black, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Моё радио',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    Text('Бесконечный микс по вашим вкусам',
                        style: TextStyle(fontSize: 11.5, color: Colors.white60)),
                  ],
                ),
              ),
              const Icon(Icons.play_arrow, size: 26),
            ],
          ),
        ),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
