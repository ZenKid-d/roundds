import 'package:flutter/foundation.dart';

/// Уровень записи в диагностическом журнале.
enum DiagLevel { info, warn, error }

extension DiagLevelX on DiagLevel {
  String get label => switch (this) {
        DiagLevel.info => 'INFO',
        DiagLevel.warn => 'WARN',
        DiagLevel.error => 'ERROR',
      };
}

/// Одна запись журнала: время, уровень, тег-подсистема и текст.
class DiagEntry {
  DiagEntry(this.level, this.tag, this.message) : time = DateTime.now();

  final DateTime time;
  final DiagLevel level;
  final String tag;
  final String message;

  String get clock {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  @override
  String toString() => '$clock ${level.label.padRight(5)} [$tag] $message';
}

/// Лёгкий внутренний журнал в память (кольцевой буфер) — без внешней
/// телеметрии. Источники по природе хрупкие (неофициальные API, протухающие
/// ключи, троттлинг), а `catch` в них раньше глотал причину молча: в поле было
/// не понять, почему трек не заиграл или поиск пустой. Теперь такие места
/// пишут сюда, а экран «Диагностика» в Настройках показывает и копирует лог.
///
/// Синглтон, потому что источники — обычные классы без доступа к Riverpod-ref;
/// им проще писать в общий журнал напрямую. UI подписывается на тот же
/// экземпляр через [diagnosticsProvider] (это [ChangeNotifier]).
class Diagnostics extends ChangeNotifier {
  Diagnostics._();
  static final Diagnostics instance = Diagnostics._();

  /// Сколько последних записей держим (старые вытесняются).
  static const capacity = 400;

  final List<DiagEntry> _entries = [];

  /// Записи от старых к новым. Копия — чтобы UI не мутировал буфер.
  List<DiagEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  void log(DiagLevel level, String tag, String message) {
    _entries.add(DiagEntry(level, tag, message));
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
    notifyListeners();
  }

  void info(String tag, String message) => log(DiagLevel.info, tag, message);
  void warn(String tag, String message) => log(DiagLevel.warn, tag, message);
  void error(String tag, String message) => log(DiagLevel.error, tag, message);

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  /// Весь журнал одним текстом — для «Скопировать» и отправки в баг-репорт.
  String export() => _entries.map((e) => e.toString()).join('\n');
}
