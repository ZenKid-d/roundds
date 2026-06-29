import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/accent_provider.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

class RoundedsApp extends ConsumerWidget {
  const RoundedsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Динамический акцент из обложки текущего трека.
    final accent =
        ref.watch(accentProvider).valueOrNull ?? AppColors.defaultAccent;

    return MaterialApp.router(
      title: 'Roundds',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(accent),
      themeAnimationDuration: const Duration(milliseconds: 500),
      routerConfig: appRouter,
    );
  }
}
