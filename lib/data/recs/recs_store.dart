import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/track.dart';
import 'recs_db.dart';
import 'recs_dedup.dart';
import 'recs_signals.dart';

/// Recs v2 — высокоуровневый стор поверх [RecsDb]: логирование событий,
/// дизлайки (hard-фильтр), cooldown, одноразовый импорт из библиотеки.
/// Дизлайки держим и в памяти — чтобы UI спрашивал синхронно и реактивно.
class RecsStore extends ChangeNotifier {
  RecsStore(this._db);
  final RecsDb _db;
  Database get _sql => _db.db;

  final Set<String> _dislikedKeys = {};
  final List<Track> _disliked = [];

  Set<String> get dislikedKeys => Set.unmodifiable(_dislikedKeys);
  List<Track> get dislikedTracks => List.unmodifiable(_disliked);

  static String keyFor(Track t) => RecsDedup.normKey(t.artist, t.title);
  int get _nowSec => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Загружает дизлайки в память (вызывается один раз при старте).
  Future<void> init() async {
    try {
      final rows = await _sql.query('dislikes', orderBy: 'ts DESC');
      _dislikedKeys.clear();
      _disliked.clear();
      for (final r in rows) {
        _dislikedKeys.add(r['track_key'] as String);
        final j = r['track_json'];
        if (j is String) {
          try {
            _disliked.add(
                Track.fromJson(jsonDecode(j) as Map<String, dynamic>));
          } catch (_) {}
        }
      }
      notifyListeners();
    } catch (_) {/* БД недоступна — работаем без дизлайков */}
  }

  bool isDisliked(Track t) => _dislikedKeys.contains(keyFor(t));

  // --- события (fire-and-forget, не блокируют плеер/UI) ---

  Future<void> _insert(Track t, SignalKind kind,
      {int? playedMs, int? durMs}) async {
    try {
      await _sql.insert('events', {
        'track_key': keyFor(t),
        'source': t.source.id,
        'artist': t.artist,
        'title': t.title,
        'ts': _nowSec,
        'dur_ms': durMs ?? t.duration?.inMilliseconds,
        'played_ms': playedMs,
        'kind': kind.id,
      });
    } catch (_) {}
  }

  void recordStart(Track t) => unawaited(_insert(t, SignalKind.start));
  void recordLike(Track t) => unawaited(_insert(t, SignalKind.like));
  void recordRepeat(Track t) => unawaited(_insert(t, SignalKind.repeat));

  /// Событие завершения трека: классифицируем скип/дослушал, обновляем cooldown.
  void recordPlayback(Track t, int playedMs, int durMs) {
    final kind =
        RecsSignals.classifyPlayback(playedMs: playedMs, durationMs: durMs);
    unawaited(() async {
      await _insert(t, kind, playedMs: playedMs, durMs: durMs);
      if (kind != SignalKind.skipHard) {
        try {
          await _sql.insert(
            'cooldowns',
            {'track_key': keyFor(t), 'last_played_ts': _nowSec},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (_) {}
      }
    }());
  }

  // --- дизлайки ---

  Future<void> setDisliked(Track t, bool on) async {
    final key = keyFor(t);
    if (on) {
      if (_dislikedKeys.add(key)) _disliked.insert(0, t);
      notifyListeners();
      unawaited(_insert(t, SignalKind.dislike));
      try {
        await _sql.insert(
          'dislikes',
          {
            'track_key': key,
            'artist': t.artist,
            'title': t.title,
            'source': t.source.id,
            'track_json': jsonEncode(t.toJson()),
            'ts': _nowSec,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (_) {}
    } else {
      await _removeDislikeKey(key);
    }
  }

  Future<void> toggleDislike(Track t) => setDisliked(t, !isDisliked(t));

  Future<void> undislikeKey(String key) => _removeDislikeKey(key);

  Future<void> _removeDislikeKey(String key) async {
    _dislikedKeys.remove(key);
    _disliked.removeWhere((e) => keyFor(e) == key);
    notifyListeners();
    try {
      await _sql.delete('dislikes', where: 'track_key = ?', whereArgs: [key]);
    } catch (_) {}
  }

  /// Одноразовый импорт существующих сигналов из библиотеки в event log:
  /// лайки → like-события, топ по прослушиваниям → complete-события (с капом).
  Future<void> importFromLibrary({
    required List<Track> liked,
    required List<MapEntry<Track, int>> topTracks,
  }) async {
    try {
      final batch = _sql.batch();
      final now = _nowSec;
      Map<String, Object?> row(Track t, SignalKind kind) => {
            'track_key': keyFor(t),
            'source': t.source.id,
            'artist': t.artist,
            'title': t.title,
            'ts': now,
            'dur_ms': t.duration?.inMilliseconds,
            'played_ms': null,
            'kind': kind.id,
          };
      for (final t in liked) {
        batch.insert('events', row(t, SignalKind.like));
      }
      for (final e in topTracks) {
        final count = e.value.clamp(0, 20); // не раздуваем лог
        for (var i = 0; i < count; i++) {
          batch.insert('events', row(e.key, SignalKind.complete));
        }
      }
      await batch.commit(noResult: true);
    } catch (_) {}
  }
}
