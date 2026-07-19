import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/play_action.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/mini_player.dart';
import '../../core/widgets/service_badge.dart';
import '../../core/widgets/track_card.dart';
import '../../domain/models/artist_profile.dart';
import '../../domain/models/source_type.dart';
import '../../domain/models/track.dart';
import '../../l10n/gen/app_localizations.dart';
import '../album/album_screen.dart';

final _artistTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, artist) async {
  return ref.read(aggregatorProvider).search(artist);
});

/// Полный профиль исполнителя (аватар/баннер/био/подписчики) — умеет отдавать
/// только SoundCloud (см. Aggregator.artistProfile). Для остальных источников
/// возвращается null, страница деградирует до обложки первого найденного трека.
final _artistProfileProvider =
    FutureProvider.family<ArtistProfile?, Track>((ref, seed) async {
  return ref.read(aggregatorProvider).artistProfile(seed);
});

class _AlbumGroup {
  const _AlbumGroup({required this.name, required this.tracks});
  final String name;
  final List<Track> tracks;
}

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({super.key, required this.artist});
  final String artist;

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  bool _albumsTab = false;

  Track? _findScSeed(List<Track> tracks) {
    for (final t in tracks) {
      if (t.source == SourceType.soundcloud && t.extra['scUserId'] != null) {
        return t;
      }
    }
    return null;
  }

  String? _firstArtwork(List<Track> tracks) {
    for (final t in tracks) {
      if ((t.artworkUrl ?? '').isNotEmpty) return t.artworkUrl;
    }
    return null;
  }

  List<_AlbumGroup> _groupAlbums(List<Track> tracks) {
    final map = <String, List<Track>>{};
    for (final t in tracks) {
      final album = t.album;
      if (album == null || album.trim().isEmpty) continue;
      map.putIfAbsent(album, () => []).add(t);
    }
    return [for (final e in map.entries) _AlbumGroup(name: e.key, tracks: e.value)];
  }

  void _toggleFollow(bool wasFollowing) {
    final l10n = AppLocalizations.of(context)!;
    ref.read(libraryProvider).toggleFollow(widget.artist);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(wasFollowing
            ? l10n.artistUnfollowSnack(widget.artist)
            : l10n.artistFollowSnack(widget.artist))));
  }

  void _startRadio(List<Track> tracks) {
    if (tracks.isEmpty) return;
    ref.read(playbackProvider).startRadio(tracks.first, tracks);
  }

  void _playAll(List<Track> tracks) {
    if (tracks.isEmpty) return;
    playTrack(ref, context, tracks.first, queue: tracks);
  }

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(_artistTracksProvider(widget.artist));
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SafeArea(
          child: Column(
            children: [
              _BackBar(title: widget.artist),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.loadErrorGeneric(e.toString()),
                        style: TextStyle(color: AppColors.white45)),
                  ),
                ),
              ),
            ],
          ),
        ),
        data: (tracks) => _buildContent(tracks, l10n),
      ),
    );
  }

  Widget _buildContent(List<Track> tracks, AppLocalizations l10n) {
    final scSeed = _findScSeed(tracks);
    final profile =
        scSeed != null ? ref.watch(_artistProfileProvider(scSeed)).value : null;
    final bannerUrl = profile?.bannerUrl ?? _firstArtwork(tracks);
    final avatarUrl = profile?.avatarUrl ?? _firstArtwork(tracks);
    final albums = _groupAlbums(tracks);
    final following = ref.watch(libraryProvider).isFollowing(widget.artist);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 220,
          pinned: true,
          backgroundColor: AppColors.background,
          leading: const _BackButton(),
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14),
            title: Text(widget.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            background: _Banner(url: bannerUrl, seed: widget.artist),
          ),
        ),
        SliverToBoxAdapter(
          child: _Header(
            artist: widget.artist,
            avatarUrl: avatarUrl,
            profile: profile,
            trackCount: tracks.length,
            following: following,
            onToggleFollow: () => _toggleFollow(following),
            onRadio: () => _startRadio(tracks),
            onPlayAll: () => _playAll(tracks),
            l10n: l10n,
          ),
        ),
        if (tracks.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Text(l10n.artistTracksEmpty,
                  style: TextStyle(color: AppColors.white45)),
            ),
          )
        else ...[
          if (albums.isNotEmpty)
            SliverToBoxAdapter(
              child: _TabSelector(
                albumsTab: _albumsTab,
                onChanged: (v) => setState(() => _albumsTab = v),
                l10n: l10n,
              ),
            ),
          if (_albumsTab)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _AlbumTile(group: albums[i], l10n: l10n),
                childCount: albums.length,
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => TrackRow(
                  track: tracks[i],
                  onTap: () => playTrack(ref, context, tracks[i], queue: tracks),
                ),
                childCount: tracks.length,
              ),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      );
}

/// Верхняя панель для состояния ошибки (без SliverAppBar — контента нет).
class _BackBar extends StatelessWidget {
  const _BackBar({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            const _BackButton(),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

/// Баннер шапки: размытая обложка (первого трека или профиля SoundCloud) с
/// затемнением к низу — то же решение, что в lyrics_screen.dart (размытая
/// обложка под текстом песни). Без URL — градиент-заглушка по хэшу имени
/// (тот же принцип, что у Artwork._placeholder, но во весь баннер).
class _Banner extends StatelessWidget {
  const _Banner({required this.url, required this.seed});
  final String? url;
  final String seed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if ((url ?? '').isNotEmpty)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
          )
        else
          _gradientPlaceholder(),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.1),
                AppColors.background,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _gradientPlaceholder() {
    final h = seed.hashCode;
    final c1 = HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.5, 0.24).toColor();
    final c2 =
        HSLColor.fromAHSL(1, ((h ~/ 7) % 360).toDouble(), 0.5, 0.1).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c1, c2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

/// Аватар, имя, статистика, био (если есть) и ряд действий (слушать всё /
/// радио / подписка).
class _Header extends StatelessWidget {
  const _Header({
    required this.artist,
    required this.avatarUrl,
    required this.profile,
    required this.trackCount,
    required this.following,
    required this.onToggleFollow,
    required this.onRadio,
    required this.onPlayAll,
    required this.l10n,
  });

  final String artist;
  final String? avatarUrl;
  final ArtistProfile? profile;
  final int trackCount;
  final bool following;
  final VoidCallback onToggleFollow;
  final VoidCallback onRadio;
  final VoidCallback onPlayAll;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final bio = profile?.bio;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Artwork(avatarUrl, size: 72, radius: 36, seed: artist),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(artist,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        Text(l10n.artistTracksCount(trackCount),
                            style: TextStyle(
                                fontSize: 12.5, color: AppColors.white60)),
                        if (profile?.followers != null)
                          Text(l10n.artistFollowersCount(profile!.followers!),
                              style: TextStyle(
                                  fontSize: 12.5, color: AppColors.white60)),
                      ],
                    ),
                  ],
                ),
              ),
              if (profile?.source != null) ...[
                const SizedBox(width: 8),
                ServiceBadge(profile!.source, size: 22),
              ],
            ],
          ),
          if ((bio ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(bio!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, color: AppColors.white60, height: 1.35)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: trackCount == 0 ? null : onPlayAll,
                  style: FilledButton.styleFrom(
                      backgroundColor: accent, foregroundColor: Colors.black),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: Text(l10n.artistPlayAll),
                ),
              ),
              const SizedBox(width: 10),
              _RoundAction(
                icon: Icons.radio,
                tooltip: l10n.artistRadioTooltip,
                onTap: trackCount == 0 ? null : onRadio,
              ),
              const SizedBox(width: 8),
              _RoundAction(
                icon: following
                    ? Icons.notifications_active
                    : Icons.notifications_none,
                tooltip:
                    following ? l10n.artistFollowingTooltip : l10n.artistFollowTooltip,
                onTap: onToggleFollow,
                active: following,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? accent.withValues(alpha: 0.18) : AppColors.white06,
      ),
      child: IconButton(
        icon: Icon(icon, size: 20, color: active ? accent : AppColors.white60),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

/// Переключатель «Треки / Альбомы». Показывается только если у артиста есть
/// хотя бы один трек с непустым album (иначе вкладка всегда пустая).
class _TabSelector extends StatelessWidget {
  const _TabSelector({
    required this.albumsTab,
    required this.onChanged,
    required this.l10n,
  });

  final bool albumsTab;
  final ValueChanged<bool> onChanged;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text(l10n.artistTracksTab)),
          ButtonSegment(value: true, label: Text(l10n.artistAlbumsTab)),
        ],
        selected: {albumsTab},
        onSelectionChanged: (s) => onChanged(s.first),
        showSelectedIcon: false,
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.group, required this.l10n});
  final _AlbumGroup group;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final seed = group.tracks.first;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Artwork(seed.artworkUrl, size: 52, seed: seed.uid, radius: 12),
      title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.artistTracksCount(group.tracks.length),
          style: TextStyle(color: AppColors.white45, fontSize: 12)),
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AlbumScreen(seed: seed))),
    );
  }
}
