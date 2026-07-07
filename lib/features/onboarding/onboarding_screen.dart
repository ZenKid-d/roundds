import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/artwork.dart';
import '../../domain/models/track.dart';
import '../home/home_screen.dart' show recommendationsProvider, dailyPlaylistsProvider;

/// Онбординг (cold start): жанры → артисты → сид профиля. Показывается при
/// первом запуске с пустой библиотекой; лайки выбранных артистов сидируют
/// профиль вкуса. Можно пропустить.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _genres = [
    'Поп', 'Рок', 'Хип-хоп', 'Рэп', 'Электроника', 'Инди', 'Джаз',
    'Классика', 'Метал', 'R&B', 'Панк', 'Фолк', 'Хаус', 'Лоу-фай',
    'Танцевальная', 'Регги',
  ];

  int _step = 0;
  final Set<String> _selectedGenres = {};
  List<Track> _suggested = const [];
  final Set<String> _selectedUids = {};
  bool _loading = false;
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _loading = true);
    final agg = ref.read(aggregatorProvider);
    final byArtist = <String, Track>{};
    for (final g in _selectedGenres) {
      try {
        final res = await agg.search(g, perSource: 12);
        for (final t in res) {
          byArtist.putIfAbsent(t.artist.toLowerCase(), () => t);
        }
      } catch (_) {}
      if (byArtist.length >= 48) break;
    }
    if (!mounted) return;
    setState(() {
      _suggested = byArtist.values.toList();
      _loading = false;
      _step = 1;
    });
  }

  Future<void> _searchArtists() async {
    final q = _searchCtl.text.trim();
    if (q.isEmpty) return;
    setState(() => _loading = true);
    List<Track> res;
    try {
      res = await ref.read(aggregatorProvider).search(q, perSource: 10);
    } catch (_) {
      res = const [];
    }
    if (!mounted) return;
    final existing = _suggested.map((t) => t.artist.toLowerCase()).toSet();
    final add = [
      for (final t in res)
        if (existing.add(t.artist.toLowerCase())) t
    ];
    setState(() {
      _suggested = [...add, ..._suggested];
      _loading = false;
      _searchCtl.clear();
    });
  }

  Future<void> _finish() async {
    final lib = ref.read(libraryProvider);
    final chosen =
        _suggested.where((t) => _selectedUids.contains(t.uid)).toList();
    for (final t in chosen) {
      await lib.toggleLike(t); // сид: лайк → событие recs → профиль вкуса
    }
    ref.read(prefsProvider).setBool('onboarded', true);
    // Пересобрать ряды/дневные с учётом новых сидов.
    ref.invalidate(recommendationsProvider);
    ref.invalidate(dailyPlaylistsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  void _skip() {
    ref.read(prefsProvider).setBool('onboarded', true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 0 ? 'Выбери жанры' : 'Выбери артистов'),
        actions: [
          TextButton(onPressed: _skip, child: const Text('Пропустить')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_step == 0 ? _genresStep() : _artistsStep()),
    );
  }

  Widget _genresStep() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            'Что ты обычно слушаешь? Выбери пару жанров — с них соберём волну.',
            style: TextStyle(color: AppColors.white60, fontSize: 13),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in _genres)
                  FilterChip(
                    label: Text(g),
                    selected: _selectedGenres.contains(g),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _selectedGenres.add(g);
                      } else {
                        _selectedGenres.remove(g);
                      }
                    }),
                  ),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selectedGenres.isEmpty ? null : _loadSuggestions,
                child: const Text('Далее'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _artistsStep() {
    final enough = _selectedUids.length >= 3;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchArtists(),
            decoration: InputDecoration(
              hintText: 'Найти артиста…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _searchArtists,
              ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: _suggested.isEmpty
              ? Center(
                  child: Text('Ничего не нашлось. Попробуй поиск выше.',
                      style: TextStyle(color: AppColors.white45)),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: _suggested.length,
                  itemBuilder: (_, i) {
                    final t = _suggested[i];
                    return _ArtistPick(
                      track: t,
                      selected: _selectedUids.contains(t.uid),
                      onTap: () => setState(() {
                        if (!_selectedUids.remove(t.uid)) {
                          _selectedUids.add(t.uid);
                        }
                      }),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: enough ? _finish : null,
                child: Text(enough
                    ? 'Готово (${_selectedUids.length})'
                    : 'Выбери минимум 3'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArtistPick extends StatelessWidget {
  const _ArtistPick({
    required this.track,
    required this.selected,
    required this.onTap,
  });
  final Track track;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Artwork(track.artworkUrl, size: 64, seed: track.uid, radius: 12),
              if (selected)
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.check_circle,
                      color: Colors.white, size: 26),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
