import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
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

/// perSource первой порции у Aggregator.search (режим «Все»).
const _baseSearchLimit = 15;

/// Размер «страницы» при фильтре по одному источнику — реальный offset/page
/// самого источника (SoundCloud/VK/Яндекс).
const _filteredPageSize = 20;

/// Сколько страниц читать сразу при первом открытии фильтра — стартовая
/// глубина ~40 (2×20).
const _initialFilteredPages = 2;

/// Насколько растить perSource режима «Все» за одно долистывание.
const _pageStep = 15;

/// Состояние постраничного поиска: текущие результаты + флаги догрузки.
class _SearchState {
  const _SearchState({
    this.results = const AsyncValue<List<Track>>.data(<Track>[]),
    this.loadingMore = false,
    this.exhausted = false,
  });

  final AsyncValue<List<Track>> results;

  /// Идёт догрузка следующей порции (список на экране остаётся, снизу спиннер).
  final bool loadingMore;

  /// Источник(и) больше не отдают новых треков — по скроллу сеть не дёргаем.
  final bool exhausted;

  _SearchState copyWith({
    AsyncValue<List<Track>>? results,
    bool? loadingMore,
    bool? exhausted,
  }) =>
      _SearchState(
        results: results ?? this.results,
        loadingMore: loadingMore ?? this.loadingMore,
        exhausted: exhausted ?? this.exhausted,
      );
}

/// Инкрементальный пагинатор поиска. Копит уже полученные страницы и при
/// долистывании догружает ТОЛЬКО следующую (без перезапроса всех 0..N), дедуп
/// по uid. Перезапускается при смене запроса/фильтра/набора источников.
final _searchProvider =
    StateNotifierProvider.autoDispose<_SearchPager, _SearchState>(
        (ref) => _SearchPager(ref));

class _SearchPager extends StateNotifier<_SearchState> {
  _SearchPager(this._ref) : super(const _SearchState()) {
    _enabled = _ref.read(settingsProvider).enabledSources.toSet();
    _ref.listen(_queryProvider, (_, __) => _restart(), fireImmediately: true);
    _ref.listen(_filterProvider, (_, __) => _restart());
    // Набор включённых источников влияет и на эффективный фильтр, и на «Все».
    // Перезапускаем только когда реально изменился состав (settingsProvider
    // шлёт уведомления и по не связанным с источниками настройкам).
    _ref.listen(settingsProvider, (_, next) {
      final now = next.enabledSources;
      if (now.length != _enabled.length || !now.containsAll(_enabled)) {
        _enabled = now.toSet();
        _restart();
      }
    });
  }

  final Ref _ref;
  Set<SourceType> _enabled = const {};

  // Аккумулятор текущего запроса. _token отсекает результаты устаревших
  // запросов (пользователь сменил запрос, пока летел ответ).
  int _token = 0;
  final List<Track> _items = [];
  final Set<String> _seen = {};
  int _nextPage = 0;

  SourceType? get _effectiveFilter {
    final raw = _ref.read(_filterProvider);
    // Источник могли выключить, пока был выбран его фильтр — ведём как «Все».
    return (raw != null && _ref.read(settingsProvider).enabledSources.contains(raw))
        ? raw
        : null;
  }

  Future<void> _restart() async {
    final token = ++_token;
    _items.clear();
    _seen.clear();
    _nextPage = 0;
    final q = _ref.read(_queryProvider).trim();
    if (q.isEmpty) {
      state = const _SearchState();
      return;
    }
    // Вставленная ссылка на видео YouTube — резолвим ровно это видео.
    final videoId = extractYoutubeVideoId(q);
    if (videoId != null) {
      await _resolveDirect(token, videoId);
      return;
    }
    state = const _SearchState(results: AsyncValue.loading());
    final initial =
        _effectiveFilter != null ? _initialFilteredPages : 1; // «Все» — 1 порция
    await _fetchMore(token, initial);
  }

  Future<void> _resolveDirect(int token, String videoId) async {
    // Прямую ссылку открываем, только если YouTube включён — иначе играли бы
    // через отключённый пользователем источник.
    if (!_ref.read(settingsProvider).enabledSources.contains(SourceType.youtube)) {
      state = _SearchState(
        results: AsyncValue.error(
          'Включите YouTube в настройках, чтобы открывать ссылки на видео.',
          StackTrace.current,
        ),
        exhausted: true,
      );
      return;
    }
    state = const _SearchState(results: AsyncValue.loading());
    try {
      final t = await _ref.read(youtubeSourceProvider).resolveVideo(videoId);
      if (token != _token) return;
      _items.add(t);
      _seen.add(t.uid);
      state = _SearchState(
          results: AsyncValue.data(List.of(_items)), exhausted: true);
    } catch (e, st) {
      if (token != _token) return;
      state =
          _SearchState(results: AsyncValue.error(e, st), exhausted: true);
    }
  }

  /// Догрузка следующей порции (вызывается при долистывании до конца).
  void loadMore() {
    if (state.loadingMore || state.exhausted) return;
    if (state.results is! AsyncData) return;
    state = state.copyWith(loadingMore: true);
    _fetchMore(_token, 1);
  }

  Future<void> _fetchMore(int token, int pages) async {
    final q = _ref.read(_queryProvider).trim();
    final filter = _effectiveFilter;
    try {
      for (var i = 0; i < pages; i++) {
        final page = await _fetchPage(q, filter, _nextPage);
        if (token != _token) return;
        _nextPage++;
        var added = 0;
        for (final t in page) {
          if (_seen.add(t.uid)) {
            _items.add(t);
            added++;
          }
        }
        // Ничего нового (источник без пагинации / выдал только дубли / пусто) —
        // дальше по скроллу не тянем.
        if (added == 0) {
          state = _SearchState(
              results: AsyncValue.data(List.of(_items)), exhausted: true);
          return;
        }
      }
      state = _SearchState(results: AsyncValue.data(List.of(_items)));
    } catch (e, st) {
      if (token != _token) return;
      // Ошибку показываем, только если совсем ничего нет; иначе оставляем уже
      // загруженное и НЕ помечаем exhausted — сбой мог быть транзиентным.
      state = _items.isEmpty
          ? _SearchState(results: AsyncValue.error(e, st))
          : _SearchState(results: AsyncValue.data(List.of(_items)));
    }
  }

  Future<List<Track>> _fetchPage(String q, SourceType? filter, int page) {
    final aggregator = _ref.read(aggregatorProvider);
    if (filter != null) {
      final source = aggregator.sourceFor(filter);
      // Источник без пагинации на page > 0 вернул бы ту же первую страницу —
      // не ходим в сеть, пусть вызывающий пометит exhausted (added == 0).
      if (page > 0 && !source.supportsPaging) return Future.value(const []);
      return source.search(q, limit: _filteredPageSize, page: page);
    }
    // «Все»: у агрегатора нет постраничности — растим perSource, дедуп в
    // [_fetchMore] оставит только новые треки.
    return aggregator.search(q, perSource: _baseSearchLimit + page * _pageStep);
  }
}

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
      // Догрузку и все гарды (исчерпано/уже грузим/нет данных) держит пагинатор.
      ref.read(_searchProvider.notifier).loadMore();
    }
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
    // Пагинатор сам перезапустится на смену запроса (слушает _queryProvider).
    ref.read(_queryProvider.notifier).state = q;
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
    final search = ref.watch(_searchProvider);
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
                  onTap: () =>
                      ref.read(_filterProvider.notifier).state = null),
              for (final s in SourceType.values)
                if (enabledSources.contains(s))
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
        Expanded(child: _body(search, submitted)),
      ],
    );
  }

  Widget _body(_SearchState search, String submitted) {
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
    if (search.loadingMore && search.results.hasValue) {
      return _resultsList(search.results.value!, submitted, loadingFooter: true);
    }

    return search.results.when(
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
