import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
