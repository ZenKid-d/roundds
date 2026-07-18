import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/service_badge.dart';
import '../../domain/models/source_type.dart';
import '../../l10n/gen/app_localizations.dart';
import '../shell/home_shell.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key, required this.current, required this.onSelect});

  final AppSection current;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Theme.of(context).colorScheme.primary;
    final settings = ref.watch(settingsProvider);
    final l10n = AppLocalizations.of(context)!;

    return Drawer(
      width: 268,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.graphic_eq, color: accent),
                    const SizedBox(width: 9),
                    const Text('Roundds',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(l10n.appTagline,
                    style:
                        TextStyle(fontSize: 11, color: AppColors.white45)),
              ),
              const SizedBox(height: 18),
              _NavItem(
                  icon: Icons.home_filled,
                  label: l10n.navHome,
                  active: current == AppSection.home,
                  accent: accent,
                  onTap: () => onSelect(AppSection.home)),
              _NavItem(
                  icon: Icons.search,
                  label: l10n.navSearch,
                  active: current == AppSection.search,
                  accent: accent,
                  onTap: () => onSelect(AppSection.search)),
              _NavItem(
                  icon: Icons.library_music,
                  label: l10n.navLibrary,
                  active: current == AppSection.library,
                  accent: accent,
                  onTap: () => onSelect(AppSection.library)),
              _NavItem(
                  icon: Icons.settings,
                  label: l10n.navSettings,
                  active: current == AppSection.settings,
                  accent: accent,
                  onTap: () => onSelect(AppSection.settings)),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: Text(l10n.drawerServicesHeader,
                    style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        color: AppColors.white45)),
              ),
              for (final s in SourceType.values)
                _ServiceRow(source: s, enabled: settings.isEnabled(s)),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Colors.white.withValues(alpha: 0.07) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon,
                  size: 20, color: active ? accent : AppColors.white60),
              const SizedBox(width: 13),
              Text(label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                    color: active ? Colors.white : AppColors.white60,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceRow extends ConsumerWidget {
  const _ServiceRow({required this.source, required this.enabled});

  final SourceType source;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(sourceReadyProvider(source));
    final l10n = AppLocalizations.of(context)!;
    final (label, color) = switch (ready) {
      AsyncData(value: true) => (l10n.serviceStatusReady, AppColors.success),
      AsyncData(value: false) => (
          enabled ? l10n.serviceStatusConfigure : l10n.serviceStatusOff,
          AppColors.white45
        ),
      AsyncLoading() => (l10n.serviceStatusLoading, AppColors.white45),
      _ => (l10n.serviceStatusError, AppColors.danger),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          ServiceBadge(source, size: 22),
          const SizedBox(width: 11),
          Text(source.shortLabel,
              style: TextStyle(fontSize: 12.5, color: AppColors.white60)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 10, color: color)),
          ),
        ],
      ),
    );
  }
}
