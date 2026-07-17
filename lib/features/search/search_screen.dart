import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/track_card.dart';
import '../../data/sources/youtube_music_source.dart';
import '../../domain/models/source_type.dart';
import '../../domain/models/track.dart';
import '../artist/artist_screen.dart';

final _queryProvider = StateProvider<String>((ref) => '');
final _filterProvider = StateProvider<SourceType?>((ref) => null);

/// Стартовые лимиты — как было раньше (perSource по умолчанию у
/// Aggregator.search / лимит при фильтре по одному источнику).
const _baseSearchLimit = 15;
const _filteredSearchLimit = 40;

/// Сколько доп. треков подгружать за один долистыванием до конца списка.
const _pageStep = 15;

/// Число уже подгруженных «страниц» сверх стартового лимита — растёт при
/// долистывании до конца, сбрасывается на 0 при новом запросе/фильтре.
final _extraPagesProvider = StateProvider<int>((ref) => 0);

final _resultsProvider = FutureProvider<List<Track>>((ref) async {
  final q = ref.watch(_queryProvider).trim();
  if (q.isEmpty) return const [];
  // Вставленная ссылка на видео YouTube — резолвим ровно это видео,
  // а не гоняем ссылку через текстовый поиск по всем источникам.
  final videoId = extractYoutubeVideoId(q);
  if (videoId != null) {
    final track = await ref.read(youtubeSourceProvider).resolveVideo(videoId);
    return [track];
  }
  final enabledSources = ref.watch(settingsProvider).enabledSources;
  final rawFilter = ref.watch(_filterProvider);
  // Источник могли выключить в настройках, пока был выбран его фильтр —
  // тогда ведём себя так, будто выбрано «Все».
  final filter =
      rawFilter != null && enabledSources.contains(rawFilter) ? rawFilter : null;
  final extra = ref.watch(_extraPagesProvider) * _pageStep;
  final aggregator = ref.read(aggregatorProvider);
  if (filter != null) {
    // Отдельный запрос именно к выбранному источнику с большим лимитом —
    // иначе фильтр просто резал бы уже загруженные для «Все» perSource=15.
    try {
      return await aggregator
          .sourceFor(filter)
          .search(q, limit: _filteredSearchLimit + extra);
    } catch (_) {
      return const [];
    }
  }
  return aggregator.search(q, perSource: _baseSearchLimit + extra);
});

/// История поиска (последние запросы), хранится в SharedPreferences.
final _recentSearchesProvider =
    StateNotifierProvider<_RecentSearches, List<String>>(
        (ref) => _RecentSearches(ref.read(prefsProvider)));

class _RecentSearches extends StateNotifier<List<String>> {
  _RecentSearches(this._prefs)
      : super(_prefs.getStringList('recent_searches') ?? const []);
  final SharedPreferences _prefs;

  void add(String q) {
    q = q.trim();
    if (q.isEmpty) return;
    final list = [
      q,
      ...state.where((e) => e.toLowerCase() != q.toLowerCase()),
    ].take(12).toList();
    state = list;
    _prefs.setStringList('recent_searches', list);
  }

  void remove(String q) {
    final list = state.where((e) => e != q).toList();
    state = list;
    _prefs.setStringList('recent_searches', list);
  }

  void clear() {
    state = const [];
    _prefs.setStringList('recent_searches', const []);
  }
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  List<String> _suggestions = const [];

  // Подгрузка следующей порции при долистывании до конца: держим уже
  // показанный список на экране (без полноэкранного спиннера) и не долбим
  // сеть повторно, если источники уже отдали всё, что могли (_exhausted).
  bool _isLoadingMore = false;
  bool _exhausted = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent > 0 && pos.pixels >= pos.maxScrollExtent - 400) {
      _maybeLoadMore();
    }
  }

  void _maybeLoadMore() {
    if (_exhausted || _isLoadingMore) return;
    final results = ref.read(_resultsProvider);
    if (!results.hasValue || results.isLoading) return;
    setState(() => _isLoadingMore = true);
    ref.read(_extraPagesProvider.notifier).state++;
  }

  /// Сбрасывает состояние подгрузки — вызывается при новом запросе/фильтре,
  /// чтобы старое «источники исчерпаны» не блокировало следующий поиск.
  void _resetPaging() {
    ref.read(_extraPagesProvider.notifier).state = 0;
    setState(() {
      _isLoadingMore = false;
      _exhausted = false;
    });
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    // Пустая строка или уже вставленная ссылка на видео — автодополнение не нужно.
    if (q.isEmpty || extractYoutubeVideoId(q) != null) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final s = await _fetchSuggestions(q);
      if (mounted && _controller.text.trim() == q) {
        setState(() => _suggestions = s);
      }
    });
  }

  Future<List<String>> _fetchSuggestions(String q) async {
    try {
      final r = await ref.read(dioProvider).get<String>(
            'https://suggestqueries.google.com/complete/search',
            queryParameters: {'client': 'firefox', 'ds': 'yt', 'q': q},
            options: Options(responseType: ResponseType.plain),
          );
      final data = jsonDecode(r.data ?? '[]');
      final list =
          (data is List && data.length > 1) ? data[1] as List : const [];
      return list.map((e) => e.toString()).take(8).toList();
    } catch (_) {
      return const [];
    }
  }

  void _submit(String v) {
    final q = v.trim();
    if (q.isEmpty) return;
    _controller.text = q;
    ref.read(_queryProvider.notifier).state = q;
    _resetPaging();
    // Сырую ссылку в историю недавних запросов не сохраняем — бесполезна для
    // повторного поиска.
    if (extractYoutubeVideoId(q) == null) {
      ref.read(_recentSearchesProvider.notifier).add(q);
    }
    setState(() => _suggestions = const []);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(_resultsProvider);
    // Если подгрузка не добавила новых треков — источники исчерпаны,
    // дальше по скроллу сеть больше не дёргаем.
    ref.listen<AsyncValue<List<Track>>>(_resultsProvider, (prev, next) {
      if (!_isLoadingMore || next.isLoading) return;
      final prevLen = prev?.valueOrNull?.length ?? 0;
      final nextLen = next.valueOrNull?.length ?? 0;
      setState(() {
        _isLoadingMore = false;
        if (nextLen <= prevLen) _exhausted = true;
      });
    });
    final enabledSources = ref.watch(settingsProvider).enabledSources;
    final rawFilter = ref.watch(_filterProvider);
    final filter =
        rawFilter != null && enabledSources.contains(rawFilter) ? rawFilter : null;
    final submitted = ref.watch(_queryProvider).trim();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'Поиск по всем сервисам',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  ref.read(_queryProvider.notifier).state = '';
                  _resetPaging();
                  setState(() => _suggestions = const []);
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
                  onTap: () {
                    ref.read(_filterProvider.notifier).state = null;
                    _resetPaging();
                  }),
              for (final s in SourceType.values)
                if (enabledSources.contains(s))
                  _Chip(
                    label: s.shortLabel,
                    active: filter == s,
                    color: s.color,
                    onTap: () {
                      ref.read(_filterProvider.notifier).state = s;
                      _resetPaging();
                    },
                  ),
            ],
          ),
        ),
        Expanded(child: _body(results, submitted)),
      ],
    );
  }

  Widget _body(AsyncValue<List<Track>> results, String submitted) {
    // Пока пользователь печатает — показываем живые подсказки.
    if (_suggestions.isNotEmpty) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          for (final s in _suggestions)
            ListTile(
              leading: Icon(Icons.search, color: AppColors.white45, size: 20),
              title: Text(s),
              trailing: Icon(Icons.north_west, color: AppColors.white45, size: 16),
              onTap: () => _submit(s),
            ),
        ],
      );
    }

    // Подгрузка следующей порции: держим уже показанный список, а не
    // перекрываем его полноэкранным спиннером на время дозапроса.
    if (_isLoadingMore && results.hasValue) {
      return _resultsList(results.value!, submitted, loadingFooter: true);
    }

    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Ошибка поиска:\n$e',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.white45)),
        ),
      ),
      data: (tracks) => _resultsList(tracks, submitted, loadingFooter: false),
    );
  }

  Widget _resultsList(List<Track> tracks, String submitted,
      {required bool loadingFooter}) {
    if (submitted.isEmpty) return _recentsOrHint();
    if (tracks.isEmpty) return _hint('Ничего не найдено.');
    // Уникальные артисты из результатов (для перехода на их страницы).
    final artists = <String>[];
    final seen = <String>{};
    for (final t in tracks) {
      if (seen.add(t.artist.toLowerCase())) artists.add(t.artist);
    }
    return ListView.builder(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: tracks.length + 1 + (loadingFooter ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == 0) return _artistsRow(artists);
        final idx = i - 1;
        if (idx >= tracks.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final t = tracks[idx];
        return TrackRow(
          track: t,
          onTap: () => playTrack(ref, context, t, queue: tracks),
        );
      },
    );
  }

  Widget _recentsOrHint() {
    final recents = ref.watch(_recentSearchesProvider);
    if (recents.isEmpty) {
      return _hint('Введите запрос — найдём по YouTube, '
          'SoundCloud и Яндексу сразу. Либо вставьте ссылку на видео YouTube.');
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
          child: Row(
            children: [
              Text('Недавние запросы',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.white60,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ref.read(_recentSearchesProvider.notifier).clear(),
                child: const Text('Очистить'),
              ),
            ],
          ),
        ),
        for (final q in recents)
          ListTile(
            leading: Icon(Icons.history, color: AppColors.white45),
            title: Text(q),
            trailing: IconButton(
              icon: Icon(Icons.close, color: AppColors.white45, size: 18),
              onPressed: () =>
                  ref.read(_recentSearchesProvider.notifier).remove(q),
            ),
            onTap: () => _submit(q),
          ),
      ],
    );
  }

  Widget _artistsRow(List<String> artists) {
    if (artists.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text('Артисты',
              style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.white60,
                  fontWeight: FontWeight.w500)),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: artists.take(12).length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final a = artists[i];
              return ActionChip(
                avatar: const Icon(Icons.person, size: 16),
                label: Text(a, style: const TextStyle(fontSize: 12.5)),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ArtistScreen(artist: a))),
              );
            },
          ),
        ),
        const Divider(height: 14),
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
