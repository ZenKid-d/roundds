import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/storage.dart';
import '../../core/theme/app_colors.dart';

/// Экран «Управление памятью»: размер загрузок и кэша, очистка.
class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  int? _downloadsBytes;
  int? _cacheBytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  Future<void> _recompute() async {
    setState(() {
      _downloadsBytes = null;
      _cacheBytes = null;
    });
    final dl = await ref.read(downloadsProvider).downloadsBytes();
    final cache = await Storage.cacheBytes();
    if (mounted) {
      setState(() {
        _downloadsBytes = dl;
        _cacheBytes = cache;
      });
    }
  }

  Future<void> _clearCache() async {
    setState(() => _busy = true);
    await Storage.clearCache();
    await _recompute();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Кэш очищен')));
    }
  }

  Future<void> _removeDownloads() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: const Text('Удалить все загрузки?'),
        content: const Text(
            'Скачанные треки станут недоступны офлайн. Библиотека и плейлисты '
            'останутся.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await ref.read(downloadsProvider).removeAll();
    await _recompute();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Загрузки удалены')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(downloadsProvider);
    final count = downloads.downloads.length;
    final total = (_downloadsBytes != null && _cacheBytes != null)
        ? _downloadsBytes! + _cacheBytes!
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Управление памятью')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TotalCard(total: total),
          const SizedBox(height: 16),
          _StorageTile(
            icon: Icons.download_done,
            title: 'Скачанные треки',
            subtitle: '$count ${_plural(count)}',
            value: _downloadsBytes,
            actionLabel: 'Удалить всё',
            onAction: (_busy || count == 0) ? null : _removeDownloads,
          ),
          const Divider(height: 24),
          _StorageTile(
            icon: Icons.image_outlined,
            title: 'Кэш (обложки и т.п.)',
            subtitle: 'Пересоздаётся при просмотре',
            value: _cacheBytes,
            actionLabel: 'Очистить',
            onAction: _busy ? null : _clearCache,
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              onPressed: _busy ? null : _recompute,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Пересчитать'),
            ),
          ),
        ],
      ),
    );
  }

  static String _plural(int n) {
    final mod10 = n % 10, mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'трек';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'трека';
    }
    return 'треков';
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total});
  final int? total;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.sd_storage_outlined, color: accent, size: 30),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Занято приложением',
                  style: TextStyle(fontSize: 12, color: AppColors.white60)),
              const SizedBox(height: 4),
              Text(total == null ? '…' : Storage.fmt(total!),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StorageTile extends StatelessWidget {
  const _StorageTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int? value;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.white60),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                  Text(value == null ? '…' : Storage.fmt(value!),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(fontSize: 11.5, color: AppColors.white45)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}
