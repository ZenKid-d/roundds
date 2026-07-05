import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/core/widgets/track_card.dart';
import 'package:roundds/domain/models/source_type.dart';
import 'package:roundds/domain/models/track.dart';

// artworkUrl намеренно null — Artwork рисует градиент-заглушку и не ходит в сеть.
const _track = Track(
  id: 'id1',
  title: 'Test Title',
  artist: 'Test Artist',
  source: SourceType.soundcloud,
);

void main() {
  testWidgets('TrackCard рисует название/артиста и реагирует на тап',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 160,
          child: TrackCard(track: _track, onTap: () => tapped++),
        ),
      ),
    ));

    expect(find.text('Test Title'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);

    await tester.tap(find.byType(TrackCard));
    await tester.pumpAndSettle(); // дать отыграть анимации масштаба
    expect(tapped, 1);
  });

  testWidgets('TrackRow рисует строку трека и реагирует на тап',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: TrackRow(track: _track, onTap: () => tapped++),
        ),
      ),
    ));

    expect(find.text('Test Title'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);

    await tester.tap(find.byType(TrackRow));
    await tester.pumpAndSettle(); // дать отыграть сплэш ListTile
    expect(tapped, 1);
  });
}
