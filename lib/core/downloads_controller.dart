import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/aggregator.dart';
import '../domain/models/track.dart';

/// Скачивание треков для оффлайн-прослушивания. Файлы — в папке документов,
/// метаданные — в SharedPreferences.
class DownloadsController extends ChangeNotifier {
  DownloadsController(this._prefs, this._dio, this._aggregator) {
    _load();
  }

  final SharedPreferences _prefs;
  final Dio _dio;
  final Aggregator _aggregator;

  final Map<String, Track> _tracks = {};
  final Map<String, String> _paths = {};
  final Set<String> _inProgress = {};

  List<Track> get downloads => _tracks.values.toList();
  bool isDownloaded(String uid) => _paths.containsKey(uid);
  bool isDownloading(String uid) => _inProgress.contains(uid);

  /// Синхронный резолвер локального файла для плеера.
  String? localPathFor(String uid) {
    final p = _paths[uid];
    if (p == null) return null;
    return File(p).existsSync() ? p : null;
  }

  void _load() {
    final raw = _prefs.getString('downloads');
    if (raw != null) {
      for (final e in (jsonDecode(raw) as List)) {
        final m = (e as Map).cast<String, dynamic>();
        final t = Track.fromJson((m['track'] as Map).cast<String, dynamic>());
        _tracks[t.uid] = t;
        _paths[t.uid] = m['path'] as String;
      }
    }
    notifyListeners();
  }

  Future<void> _persist() => _prefs.setString(
        'downloads',
        jsonEncode(_tracks.values
            .map((t) => {'track': t.toJson(), 'path': _paths[t.uid]})
            .toList()),
      );

  Future<void> download(Track track) async {
    if (isDownloaded(track.uid) || isDownloading(track.uid)) return;
    _inProgress.add(track.uid);
    notifyListeners();
    try {
      final stream = await _aggregator.resolveStreamWithFallback(track);
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/downloads');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final safe = track.uid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
      final path = '${folder.path}/$safe.audio';
      await _dio.download(
        stream.uri.toString(),
        path,
        options: Options(headers: stream.headers),
      );
      _tracks[track.uid] = track;
      _paths[track.uid] = path;
      await _persist();
    } catch (_) {
      // ошибку проглатываем — в UI трек просто не отметится скачанным
    } finally {
      _inProgress.remove(track.uid);
      notifyListeners();
    }
  }

  Future<void> remove(String uid) async {
    final p = _paths[uid];
    if (p != null) {
      try {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _tracks.remove(uid);
    _paths.remove(uid);
    await _persist();
    notifyListeners();
  }
}
