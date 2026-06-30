import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/routing/app_router.dart';
import 'core/theme/accent_provider.dart';
import 'core/theme/app_theme.dart';

class RoundedsApp extends ConsumerWidget {
  const RoundedsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(effectiveAccentProvider);
    final ts = ref.watch(themeSettingsProvider);

    return MaterialApp.router(
      title: 'Roundds',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(
        accent: accent,
        radius: ts.radius,
        systemFont: ts.systemFont,
      ),
      themeAnimationDuration: const Duration(milliseconds: 500),
      routerConfig: appRouter,
    );
  }
}
