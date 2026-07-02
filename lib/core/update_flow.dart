import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'update_controller.dart';

/// Проверяет обновление и показывает диалог с описанием изменений. Скачивание
/// идёт в ФОНЕ (через [UpdateController]) — прогресс и кнопку «Установить»
/// показывает плавающий баннер, поэтому установить можно в любой момент.
///
/// [silent] — при true молчим, если обновления нет или проверка не удалась
/// (тихая авто-проверка при запуске). При false (кнопка) сообщаем результат.
Future<void> checkForUpdate(
  BuildContext context,
  WidgetRef ref, {
  bool silent = true,
}) async {
  final ctl = ref.read(updateControllerProvider);

  // Уже скачано — сразу предлагаем установить.
  if (ctl.isReady) {
    if (context.mounted) _promptInstall(context, ctl);
    return;
  }
  if (ctl.isDownloading) {
    if (!silent && context.mounted) {
      _snack(context, 'Обновление уже загружается…');
    }
    return;
  }

  final info = await ctl.check();

  if (info == null) {
    if (!silent && context.mounted) {
      _snack(
          context,
          ctl.stage == UpdateStage.error
              ? 'Не удалось проверить обновления'
              : 'У вас установлена последняя версия');
    }
    return;
  }
  if (!context.mounted) return;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Обновление ${info.version}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 340),
        child: SingleChildScrollView(
          child: Text(
            info.notes.trim().isEmpty
                ? 'Доступна новая версия. Скачать сейчас?'
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
          child: const Text('Скачать в фоне'),
        ),
      ],
    ),
  );
  if (go != true) return;

  // Запускаем фоновую загрузку и не ждём её — прогресс покажет баннер.
  ctl.download();
  if (context.mounted) {
    _snack(context, 'Загрузка обновления началась — можно продолжать слушать');
  }
}

/// Диалог «скачано — установить сейчас?».
Future<void> _promptInstall(BuildContext context, UpdateController ctl) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Обновление ${ctl.info?.version ?? ''} готово'),
      content: const Text('Установить сейчас?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Позже')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Установить')),
      ],
    ),
  );
  if (go == true) ctl.install();
}

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
