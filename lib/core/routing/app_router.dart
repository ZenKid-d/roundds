import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/player/now_playing_screen.dart';
import '../../features/shell/home_shell.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeShell()),
    GoRoute(
      path: '/player',
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
  ],
);
