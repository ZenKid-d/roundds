import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/aggregator.dart';
import '../domain/models/track.dart';
import 'notifications.dart';

/// Скачивание треков для оффлайн-прослушивания. Файлы — в папке документов,
/// метаданные — в SharedPreferences.
class DownloadsController extends ChangeNotifier {
  DownloadsController(this._prefs, this._dio, this._aggregator) {
    _load();
  }

  final SharedPreferences _prefs;
  final Dio _dio;
  final Aggregator _aggregator;
  final NotificationService _notif = NotificationService();

  final Map<String, Track> _tracks = {};
  final Map<String, String> _paths = {};
  final Set<String> _inProgress = {};
  final Map<String, double> _progress = {};
  final Map<String, Track> _downloading = {};

  double _playlistProgress = 0;
  String? _playlistName;
  bool _playlistBusy = false;

  List<Track> get downloads => _tracks.values.toList();
  List<Track> get inProgress => _downloading.values.toList();
  bool isDownloaded(String uid) => _paths.containsKey(uid);
  bool isDownloading(String uid) => _inProgress.contains(uid);
  double progressFor(String uid) => _progress[uid] ?? 0;
  double get playlistProgress => _playlistProgress;
  String? get playlistName => _playlistName;
  bool get playlistBusy => _playlistBusy;

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

  /// Скачивает один трек. Возвращает true, если файл уже есть или успешно
  /// скачан; false — если не удалось (ошибка потока/сети).
  Future<bool> download(Track track, {bool notify = true}) async {
    if (isDownloaded(track.uid)) return true;
    if (isDownloading(track.uid)) return false;
    _inProgress.add(track.uid);
    _downloading[track.uid] = track;
    _progress[track.uid] = 0;
    notifyListeners();
    var ok = false;
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
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _progress[track.uid] = received / total;
            notifyListeners();
          }
        },
      );
      _tracks[track.uid] = track;
      _paths[track.uid] = path;
      await _persist();
      ok = true;
      if (notify) {
        await _notif.show('Трек скачан', '${track.artist} — ${track.title}');
      }
    } catch (_) {
      // не удалось — вернём false, вызывающий может повторить
    } finally {
      _inProgress.remove(track.uid);
      _downloading.remove(track.uid);
      _progress.remove(track.uid);
      notifyListeners();
    }
    return ok;
  }

  /// Скачать весь плейлист. Каждый трек — до 3 попыток, чтобы временные сбои
  /// сети/потока не приводили к пропуску. Уведомление — одно, в конце.
  Future<void> downloadPlaylist(String name, List<Track> tracks) async {
    if (_playlistBusy || tracks.isEmpty) return;
    _playlistBusy = true;
    _playlistName = name;
    _playlistProgress = 0;
    notifyListeners();
    var done = 0;
    var failed = 0;
    for (final t in tracks) {
      if (!isDownloaded(t.uid)) {
        var ok = false;
        for (var attempt = 0; attempt < 3 && !ok; attempt++) {
          ok = await download(t, notify: false);
          if (!ok) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        if (!ok) failed++;
      }
      done++;
      _playlistProgress = done / tracks.length;
      notifyListeners();
    }
    _playlistBusy = false;
    _playlistName = null;
    _playlistProgress = 0;
    notifyListeners();
    final total = tracks.length;
    final body = failed == 0
        ? '$name · $total треков'
        : '$name · скачано ${total - failed}, не удалось $failed';
    await _notif.show('Плейлист скачан', body, id: 1);
  }

  /// Суммарный размер скачанных файлов, в байтах.
  Future<int> downloadsBytes() async {
    var total = 0;
    for (final p in _paths.values) {
      try {
        final f = File(p);
        if (f.existsSync()) total += await f.length();
      } catch (_) {}
    }
    return total;
  }

  /// Удаляет все скачанные треки и их файлы.
  Future<void> removeAll() async {
    for (final p in _paths.values) {
      try {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _tracks.clear();
    _paths.clear();
    await _persist();
    notifyListeners();
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
