import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/core/diagnostics.dart';

void main() {
  final diag = Diagnostics.instance;

  setUp(diag.clear);

  test('пишет записи разных уровней в порядке добавления', () {
    diag.info('a', 'first');
    diag.warn('b', 'second');
    diag.error('c', 'third');
    final e = diag.entries;
    expect(e.map((x) => x.message).toList(), ['first', 'second', 'third']);
    expect(e.map((x) => x.level).toList(),
        [DiagLevel.info, DiagLevel.warn, DiagLevel.error]);
    expect(e.map((x) => x.tag).toList(), ['a', 'b', 'c']);
  });

  test('кольцевой буфер вытесняет старые записи сверх ёмкости', () {
    for (var i = 0; i < Diagnostics.capacity + 50; i++) {
      diag.info('t', 'msg$i');
    }
    final e = diag.entries;
    expect(e.length, Diagnostics.capacity);
    // Первые 50 вытеснены — самая старая теперь msg50.
    expect(e.first.message, 'msg50');
    expect(e.last.message, 'msg${Diagnostics.capacity + 49}');
  });

  test('clear очищает журнал', () {
    diag.info('t', 'x');
    expect(diag.isEmpty, isFalse);
    diag.clear();
    expect(diag.isEmpty, isTrue);
    expect(diag.entries, isEmpty);
  });

  test('export форматирует строки с уровнем и тегом', () {
    diag.warn('src', 'boom');
    final line = diag.export();
    expect(line, contains('WARN'));
    expect(line, contains('[src]'));
    expect(line, contains('boom'));
  });

  test('notifyListeners срабатывает на запись и на очистку', () {
    var notifications = 0;
    void listener() => notifications++;
    diag.addListener(listener);
    diag.info('t', 'x'); // +1
    diag.clear(); // +1
    diag.clear(); // пусто — не уведомляет
    diag.removeListener(listener);
    expect(notifications, 2);
  });
}
