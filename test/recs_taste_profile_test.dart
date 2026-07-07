import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/data/recs/recs_signals.dart';
import 'package:roundds/data/recs/taste_profile.dart';

void main() {
  const day = 86400;

  group('decayFactor (затухание)', () {
    test('t=0 → 1.0', () => expect(decayFactor(0), 1.0));
    test('half-life 30д → 0.5',
        () => expect(decayFactor(30 * day), closeTo(0.5, 1e-9)));
    test('две half-life 60д → 0.25',
        () => expect(decayFactor(60 * day), closeTo(0.25, 1e-9)));
    test('отрицательное Δt клемпится к 1.0',
        () => expect(decayFactor(-100), 1.0));
  });

  group('TasteProfileBuilder.build', () {
    test('свежий лайк даёт полный вес артиста', () {
      final p = TasteProfileBuilder.build(
        const [
          ProfileEvent(artist: 'Artist A', kind: SignalKind.like, tsSec: 1000)
        ],
        nowSec: 1000,
      );
      expect(p.longArtists['artist a'], closeTo(1.5, 1e-9));
      expect(p.isKnownArtist('artist a'), isTrue);
    });

    test('лайк 30 дней назад весит вдвое меньше свежего', () {
      const now = 100 * day;
      final p = TasteProfileBuilder.build(
        const [
          ProfileEvent(artist: 'A', kind: SignalKind.like, tsSec: now - 30 * day)
        ],
        nowSec: now,
      );
      expect(p.longArtists['a'], closeTo(1.5 * 0.5, 1e-9));
    });

    test('жёсткий скип наполняет негативный профиль и топит долгосрочный', () {
      final p = TasteProfileBuilder.build(
        const [ProfileEvent(artist: 'B', kind: SignalKind.skipHard, tsSec: 0)],
        nowSec: 0,
      );
      expect(p.longArtists['b'], closeTo(-1.0, 1e-9));
      expect(p.negArtists['b'], closeTo(1.0, 1e-9));
      expect(p.isKnownArtist('b'), isTrue); // слышал, пусть и скипнул
    });

    test('нейтральный start только помечает heard, без веса', () {
      final p = TasteProfileBuilder.build(
        const [ProfileEvent(artist: 'C', kind: SignalKind.start, tsSec: 0)],
        nowSec: 0,
      );
      expect(p.longArtists.containsKey('c'), isFalse);
      expect(p.isKnownArtist('c'), isTrue);
    });

    test('теги наследуют вес сигнала', () {
      final p = TasteProfileBuilder.build(
        const [
          ProfileEvent(
              artist: 'A',
              kind: SignalKind.like,
              tsSec: 0,
              tags: ['Chill', 'Indie']),
        ],
        nowSec: 0,
      );
      expect(p.longTags['chill'], closeTo(1.5, 1e-9));
      expect(p.longTags['indie'], closeTo(1.5, 1e-9));
    });

    test('краткосрочный профиль — последние N событий без затухания', () {
      const now = 100 * day;
      final p = TasteProfileBuilder.build(
        const [
          ProfileEvent(artist: 'A', kind: SignalKind.like, tsSec: now - 50 * day),
          ProfileEvent(artist: 'B', kind: SignalKind.like, tsSec: now),
        ],
        nowSec: now,
        shortWindow: 1,
      );
      expect(p.shortArtists.containsKey('b'), isTrue);
      expect(p.shortArtists.containsKey('a'), isFalse);
      expect(p.shortArtists['b'], closeTo(1.5, 1e-9)); // без затухания
    });
  });

  group('TasteProfile.artistAffinity (mix)', () {
    test('α·short + (1−α)·long', () {
      const p = TasteProfile(
        longArtists: {'a': 2.0},
        shortArtists: {'a': 0.0},
        heardArtists: {'a'},
      );
      expect(p.artistAffinity('a', alpha: 0.5), closeTo(1.0, 1e-9));
      expect(p.artistAffinity('a', alpha: 0.0), closeTo(2.0, 1e-9));
      expect(p.artistAffinity('a', alpha: 1.0), closeTo(0.0, 1e-9));
    });
  });

  group('TasteProfile snapshot', () {
    test('encode/decode round-trip', () {
      final p = TasteProfileBuilder.build(
        const [
          ProfileEvent(
              artist: 'A', kind: SignalKind.like, tsSec: 0, tags: ['pop']),
          ProfileEvent(artist: 'B', kind: SignalKind.skipHard, tsSec: 0),
        ],
        nowSec: 0,
      );
      final r = TasteProfile.decode(p.encode());
      expect(r.longArtists['a'], closeTo(p.longArtists['a']!, 1e-9));
      expect(r.negArtists['b'], closeTo(p.negArtists['b']!, 1e-9));
      expect(r.longTags['pop'], closeTo(p.longTags['pop']!, 1e-9));
      expect(r.isKnownArtist('a'), isTrue);
    });

    test('битый снапшот → пустой профиль', () {
      expect(TasteProfile.decode('{not json').longArtists, isEmpty);
    });
  });
}
