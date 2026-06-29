import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/track_card.dart';
import '../../domain/models/source_type.dart';
import '../../domain/models/track.dart';

final _queryProvider = StateProvider<String>((ref) => '');
final _filterProvider = StateProvider<SourceType?>((ref) => null);

final _resultsProvider = FutureProvider<List<Track>>((ref) async {
  final q = ref.watch(_queryProvider).trim();
  if (q.isEmpty) return const [];
  final results = await ref.read(aggregatorProvider).search(q);
  final filter = ref.watch(_filterProvider);
  if (filter == null) return results;
  return results.where((t) => t.source == filter).toList();
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(_resultsProvider);
    final filter = ref.watch(_filterProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) =>
                ref.read(_queryProvider.notifier).state = v,
            decoration: InputDecoration(
              hintText: 'Поиск по всем сервисам',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  ref.read(_queryProvider.notifier).state = '';
                },
              ),
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _Chip(
                  label: 'Все',
                  active: filter == null,
                  onTap: () =>
                      ref.read(_filterProvider.notifier).state = null),
              for (final s in SourceType.values)
                _Chip(
                  label: s.shortLabel,
                  active: filter == s,
                  color: s.color,
                  onTap: () =>
                      ref.read(_filterProvider.notifier).state = s,
                ),
            ],
          ),
        ),
        Expanded(
          child: results.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Ошибка поиска:\n$e',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.white45)),
              ),
            ),
            data: (tracks) {
              if (ref.watch(_queryProvider).trim().isEmpty) {
                return _hint('Введите запрос — найдём по YouTube, '
                    'SoundCloud и Яндексу сразу.');
              }
              if (tracks.isEmpty) return _hint('Ничего не найдено.');
              return ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (_, i) => TrackRow(
                  track: tracks[i],
                  onTap: () =>
                      playTrack(ref, context, tracks[i], queue: tracks),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _hint(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.white45, fontSize: 13)),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? c.withValues(alpha: 0.18) : AppColors.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active ? c : Colors.transparent, width: 1),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12.5,
                color: active ? Colors.white : AppColors.white60,
              )),
        ),
      ),
    );
  }
}
