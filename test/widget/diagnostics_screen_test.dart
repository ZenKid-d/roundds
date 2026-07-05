import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/core/diagnostics.dart';
import 'package:roundds/features/settings/diagnostics_screen.dart';

Widget _wrap() => const ProviderScope(
      child: MaterialApp(home: DiagnosticsScreen()),
    );

void main() {
  setUp(Diagnostics.instance.clear);

  testWidgets('пустой журнал показывает подсказку', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.textContaining('Пока пусто'), findsOneWidget);
  });

  testWidgets('записи журнала отображаются (сообщение + тег)', (tester) async {
    Diagnostics.instance.error('yt.resolve', 'поток недоступен');
    await tester.pumpWidget(_wrap());
    expect(find.text('поток недоступен'), findsOneWidget);
    expect(find.textContaining('yt.resolve'), findsOneWidget);
  });

  testWidgets('кнопка очистки опустошает журнал', (tester) async {
    Diagnostics.instance.warn('t', 'to be cleared');
    await tester.pumpWidget(_wrap());
    expect(find.text('to be cleared'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('to be cleared'), findsNothing);
    expect(find.textContaining('Пока пусто'), findsOneWidget);
  });
}
