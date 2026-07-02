import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'update_service.dart';

/// Проверка обновлений и весь UX: диалог с описанием изменений →
/// прогресс скачивания → запуск установщика.
///
/// [silent] — при true ничего не показываем, если обновления нет и если
/// проверка упала (тихая авто-проверка при запуске). При false (кнопка в
/// настройках) сообщаем результат в любом случае.
Future<void> checkForUpdate(
  BuildContext context,
  WidgetRef ref, {
  bool silent = true,
}) async {
  UpdateInfo? info;
  try {
    info = await ref.read(updateServiceProvider).check();
  } catch (_) {
    if (!silent && context.mounted) {
      _snack(context, 'Не удалось проверить обновления');
    }
    return;
  }

  if (info == null) {
    if (!silent && context.mounted) {
      _snack(context, 'У вас установлена последняя версия');
    }
    return;
  }
  if (!context.mounted) return;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Обновление ${info!.version}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 340),
        child: SingleChildScrollView(
          child: Text(
            info.notes.trim().isEmpty
                ? 'Доступна новая версия. Обновить сейчас?'
                : info.notes.trim(),
            style: const TextStyle(height: 1.4),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Позже'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Обновить'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  final progress = ValueNotifier<double>(0);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Скачивание обновления'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, v, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: v <= 0 ? null : v,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 12),
            Text(v <= 0 ? 'Подготовка…' : '${(v * 100).round()}%'),
          ],
        ),
      ),
    ),
  );

  try {
    await ref.read(updateServiceProvider).downloadAndInstall(
          info,
          onProgress: (p) => progress.value = p,
        );
    if (context.mounted) Navigator.pop(context); // закрыть прогресс
  } catch (_) {
    if (context.mounted) {
      Navigator.pop(context);
      _snack(context, 'Ошибка при загрузке обновления');
    }
  } finally {
    progress.dispose();
  }
}

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
