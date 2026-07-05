import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';

/// Внутренний журнал диагностики: последние события источников (поиск, резолв
/// потока, троттлинг, обновление ключей). Помогает понять в поле, почему трек
/// не заиграл или поиск пуст — без внешней телеметрии. Данные только в памяти,
/// сбрасываются при перезапуске.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diag = ref.watch(diagnosticsProvider);
    // Новые сверху.
    final entries = diag.entries.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Диагностика'),
        actions: [
          IconButton(
            tooltip: 'Скопировать журнал',
            icon: const Icon(Icons.copy_all),
            onPressed: entries.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                        ClipboardData(text: diag.export()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Журнал скопирован')),
                      );
                    }
                  },
          ),
          IconButton(
            tooltip: 'Очистить',
            icon: const Icon(Icons.delete_outline),
            onPressed: entries.isEmpty ? null : diag.clear,
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'Пока пусто. Здесь появятся события источников — ошибки '
                  'поиска, недоступные потоки, троттлинг YouTube и т.п. '
                  'Если что-то не играет, зайди сюда и скопируй журнал.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.white45),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: AppColors.white06,
              ),
              itemBuilder: (_, i) => _EntryTile(entries[i]),
            ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.entry);

  final DiagEntry entry;

  Color get _color => switch (entry.level) {
        DiagLevel.info => AppColors.white45,
        DiagLevel.warn => AppColors.warning,
        DiagLevel.error => AppColors.youtube,
      };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(Icons.circle, size: 10, color: _color),
      title: Text(
        entry.message,
        style: const TextStyle(fontSize: 12.5),
      ),
      subtitle: Text(
        '${entry.clock} · ${entry.tag}',
        style: TextStyle(color: AppColors.white45, fontSize: 11),
      ),
    );
  }
}
