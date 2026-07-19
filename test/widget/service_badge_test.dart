import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/core/widgets/service_badge.dart';
import 'package:roundds/domain/models/source_type.dart';

/// [ServiceBadge] / [ServicePill] — бейдж источника и пилюля «через <Сервис>»
/// на экране плеера. Пилюля показывает приписку «(нет в <origin>)» только при
/// межисточниковой подмене (origin != null) — это видимое пользователю
/// последствие кросс-источника, поэтому покрытие должно быть.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(body: Center(child: child)),
        ),
      );

  group('ServiceBadge', () {
    testWidgets('рисует бейдж для SoundCloud', (tester) async {
      await pump(tester, const ServiceBadge(SourceType.soundcloud));
      expect(find.byType(ServiceBadge), findsOneWidget);
      expect(find.byType(FaIcon), findsOneWidget); // иконка внутри бейджа
    });

    testWidgets('рисует бейдж для всех источников', (tester) async {
      for (final s in SourceType.values) {
        await pump(tester, ServiceBadge(s));
        expect(find.byType(ServiceBadge), findsOneWidget,
            reason: 'бейдж для ${s.label}');
      }
    });
  });

  group('ServicePill', () {
    testWidgets('без origin — только «через <сервис>», без приписки', (tester) async {
      await pump(tester, const ServicePill(SourceType.youtube));
      expect(find.textContaining('через YT Music'), findsOneWidget);
      // приписки про «нет в» быть не должно — родной источник играет сам
      expect(find.textContaining('нет в'), findsNothing);
    });

    testWidgets('с origin — показывает «(нет в <origin>)» при подмене', (tester) async {
      // Трек SoundCloud, но играет с YouTube (Go+/блокировка) — пользователь
      // должен видеть, откуда реально играет и где нет.
      await pump(tester, const ServicePill(
        SourceType.youtube,
        origin: SourceType.soundcloud,
      ));
      expect(find.textContaining('через YT Music'), findsOneWidget);
      expect(find.textContaining('нет в SoundCloud'), findsOneWidget);
    });

    testWidgets('короткая подпись по shortLabel для каждого источника', (tester) async {
      for (final s in SourceType.values) {
        await pump(tester, ServicePill(s));
        expect(find.textContaining('через ${s.shortLabel}'), findsOneWidget,
            reason: 'shortLabel для ${s.label}');
      }
    });
  });
}
