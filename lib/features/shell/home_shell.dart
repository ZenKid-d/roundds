import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/update_flow.dart';
import '../../core/widgets/mini_player.dart';
import '../drawer/app_drawer.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

/// Разделы приложения (переключаются из бокового меню).
enum AppSection { home, search, library, settings }

extension AppSectionX on AppSection {
  String get title => switch (this) {
        AppSection.home => 'Roundds',
        AppSection.search => 'Поиск',
        AppSection.library => 'Медиатека',
        AppSection.settings => 'Настройки',
      };
}

/// Главная оболочка: Scaffold с боковым меню (Drawer), переключаемым телом
/// и закреплённым мини-плеером снизу.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  AppSection _section = AppSection.home;

  @override
  void initState() {
    super.initState();
    // Тихая авто-проверка обновлений после первого кадра.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkForUpdate(context, ref, silent: true);
    });
  }

  void _select(AppSection s) {
    setState(() => _section = s);
    Navigator.of(context).pop(); // закрыть Drawer
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(current: _section, onSelect: _select),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(
              title: _section.title,
              showSearch: _section != AppSection.search,
              onSearch: () => setState(() => _section = AppSection.search),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0, 0.02), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_section),
                  child: _body(),
                ),
              ),
            ),
            const _UpdateBanner(),
            const MiniPlayer(),
          ],
        ),
      ),
    );
  }

  Widget _body() => switch (_section) {
        AppSection.home => const HomeScreen(),
        AppSection.search => const SearchScreen(),
        AppSection.library => const LibraryScreen(),
        AppSection.settings => const SettingsScreen(),
      };
}

/// Плавающий баннер обновления: прогресс фоновой загрузки и кнопка
/// «Установить», когда APK скачан (установить можно в любой момент).
class _UpdateBanner extends ConsumerWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.watch(updateControllerProvider);
    if (!ctl.bannerVisible) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.primary;
    final version = ctl.info?.version ?? '';

    if (ctl.isDownloading) {
      final pct = (ctl.progress * 100).round();
      return Container(
        color: AppColors.surface1,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  value: ctl.progress == 0 ? null : ctl.progress,
                  strokeWidth: 2,
                  color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Загрузка обновления $version… $pct%',
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      );
    }

    // Готово к установке.
    return Container(
      color: AppColors.surface1,
      padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
      child: Row(
        children: [
          Icon(Icons.system_update, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Обновление $version готово',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w500)),
          ),
          TextButton(
            onPressed: () => ref.read(updateControllerProvider).install(),
            child: const Text('Установить'),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Скрыть',
            onPressed: () =>
                ref.read(updateControllerProvider).dismissBanner(),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.showSearch,
    required this.onSearch,
  });

  final String title;
  final bool showSearch;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          showSearch
              ? IconButton(
                  icon: const Icon(Icons.search), onPressed: onSearch)
              : const SizedBox(width: 48),
        ],
      ),
    );
  }
}
