import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/player/now_playing_screen.dart';
import '../../features/shell/home_shell.dart';
import '../../features/charts/charts_screen.dart';
import '../../features/player/equalizer_screen.dart';
import '../../features/settings/appearance_screen.dart';
import '../../features/settings/storage_screen.dart';
import '../../features/settings/blacklist_screen.dart';
import '../../features/settings/dislikes_screen.dart';
import '../../features/settings/diagnostics_screen.dart';
import '../../features/stats/stats_screen.dart';
import '../../features/artist/followed_artists_screen.dart';

/// Именованные пути навигации. Используются через context.push(name),
/// чтобы навигация была в одном месте (а не через MaterialPageRoute в
/// каждом виджете) и поддерживала deep links.
///
/// Параметризованные экраны (artist/album/playlist/tracklist) пока
/// остаются на MaterialPageRoute — они требуют path parameters, что
/// в go_router 14 делается через :param и extra. Перевод запланирован
/// вместе с миграцией go_router 14→17 (Этап 9), т.к. там API маршрутов
/// всё равно меняется.
class Routes {
  static const home = '/';
  static const player = '/player';
  static const charts = '/charts';
  static const equalizer = '/equalizer';
  static const appearance = '/settings/appearance';
  static const stats = '/stats';
  static const storage = '/settings/storage';
  static const blacklist = '/settings/blacklist';
  static const dislikes = '/settings/dislikes';
  static const diagnostics = '/settings/diagnostics';
  static const followedArtists = '/followed-artists';
}

final appRouter = GoRouter(
  routes: [
    GoRoute(path: Routes.home, builder: (_, __) => const HomeShell()),
    GoRoute(
      path: Routes.player,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const NowPlayingScreen(),
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, anim, __, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                .animate(curved),
            child: child,
          );
        },
      ),
    ),
    // Вторичные экраны без параметров — именованные маршруты вместо
    // разрозненных MaterialPageRoute.push.
    GoRoute(path: Routes.charts, builder: (_, __) => const ChartsScreen()),
    GoRoute(
        path: Routes.equalizer, builder: (_, __) => const EqualizerScreen()),
    GoRoute(
        path: Routes.appearance,
        builder: (_, __) => const AppearanceScreen()),
    GoRoute(path: Routes.stats, builder: (_, __) => const StatsScreen()),
    GoRoute(path: Routes.storage, builder: (_, __) => const StorageScreen()),
    GoRoute(
        path: Routes.blacklist, builder: (_, __) => const BlacklistScreen()),
    GoRoute(
        path: Routes.dislikes, builder: (_, __) => const DislikesScreen()),
    GoRoute(
        path: Routes.diagnostics,
        builder: (_, __) => const DiagnosticsScreen()),
    GoRoute(
        path: Routes.followedArtists,
        builder: (_, __) => const FollowedArtistsScreen()),
  ],
);
