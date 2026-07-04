import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/aggregator.dart';
import '../domain/models/source_type.dart';
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
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/downloads');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final safe = track.uid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
      final path = '${folder.path}/$safe.audio';

      void onProg(int received, int total) {
        if (total > 0) {
          _progress[track.uid] = received / total;
          notifyListeners();
        }
      }

      ok = await _downloadTrackTo(track, path, onProg);
      if (ok) {
        _tracks[track.uid] = track;
        _paths[track.uid] = path;
        await _persist();
        if (notify) {
          await _notif.show('Трек скачан', '${track.artist} — ${track.title}');
        }
      } else {
        _safeDelete(path); // подчистим частичный/битый файл
      }
    } catch (e) {
      debugPrint('Не удалось скачать ${track.uid}: $e');
      // не удалось — вернём false, вызывающий может повторить
    } finally {
      _inProgress.remove(track.uid);
      _downloading.remove(track.uid);
      _progress.remove(track.uid);
      notifyListeners();
    }
    return ok;
  }

  /// Скачивает трек в [path], пробуя стратегии по порядку до валидного файла:
  ///  1. Нативный загрузчик источника (YouTube качает чанками — обходит 403).
  ///  2. Прямой GET progressive-ссылки через dio (HLS так скачать нельзя —
  ///     это плейлист `.m3u8`, а не аудио).
  ///  3. Та же песня с YouTube нативно (если источник отдал только HLS/не смог).
  /// Каждый успех проверяется на «похоже на аудио» (размер файла).
  Future<bool> _downloadTrackTo(
      Track track, String path, void Function(int, int) onProg) async {
    // 1. Нативный загрузчик источника.
    if (await _aggregator.sourceFor(track.source).downloadTo(track, path,
            onProgress: onProg) &&
        _looksValid(path)) {
      return true;
    }
    // 2. По URL через dio (progressive), не HLS.
    try {
      final stream = await _aggregator.resolveStreamWithFallback(track);
      if (!_isHls(stream.uri)) {
        await _dio.download(stream.uri.toString(), path,
            options: Options(headers: stream.headers),
            onReceiveProgress: onProg);
        if (_looksValid(path)) return true;
      }
    } catch (_) {/* пробуем YouTube-фолбэк ниже */}
    // 3. Источник отдал только HLS / не смог — качаем ту же песню с YouTube.
    if (track.source != SourceType.youtube) {
      final yt = await _aggregator.youtubeMatch(track);
      if (yt != null &&
          await _aggregator.sourceFor(SourceType.youtube).downloadTo(yt, path,
              onProgress: onProg) &&
          _looksValid(path)) {
        return true;
      }
    }
    return false;
  }

  /// HLS-плейлист (`.m3u8`) нельзя скачать простым GET — это не аудиофайл.
  bool _isHls(Uri uri) =>
      uri.path.toLowerCase().contains('.m3u8') ||
      uri.toString().toLowerCase().contains('m3u8');

  /// Грубая проверка целостности: настоящий аудиофайл заведомо больше 16 КБ
  /// (m3u8-манифест/пустышка — единицы КБ). Отсекает «скачанный» мусор.
  bool _looksValid(String path) {
    try {
      return File(path).lengthSync() >= 16 * 1024;
    } catch (_) {
      return false;
    }
  }

  void _safeDelete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Скачать весь плейлист. Треки качаются ПАРАЛЛЕЛЬНО (пул воркеров) — это
  /// заметно быстрее последовательной загрузки. Каждый трек — до 3 попыток,
  /// чтобы временные сбои не приводили к пропуску. Прогресс — в постоянном
  /// уведомлении и в UI; итог — одним уведомлением.
  static const int _dlNotifId = 1;
  static const int _dlConcurrency = 4;

  Future<void> downloadPlaylist(String name, List<Track> tracks) async {
    if (_playlistBusy || tracks.isEmpty) return;
    _playlistBusy = true;
    _playlistName = name;
    _playlistProgress = 0;
    notifyListeners();

    final total = tracks.length;
    final queue = tracks.where((t) => !isDownloaded(t.uid)).toList();
    var done = total - queue.length; // уже скачанные засчитываем сразу
    var failed = 0;

    _playlistProgress = total == 0 ? 1 : done / total;
    notifyListeners();
    await _notif.showProgress('Скачивание: $name', '$done / $total',
        progress: done, max: total, id: _dlNotifId);

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final t = queue.removeAt(0); // атомарно между await'ами
        var ok = false;
        for (var attempt = 0; attempt < 3 && !ok; attempt++) {
          ok = await download(t, notify: false);
          if (!ok) await Future.delayed(const Duration(milliseconds: 500));
        }
        if (!ok) failed++;
        done++;
        _playlistProgress = done / total;
        notifyListeners();
        await _notif.showProgress('Скачивание: $name', '$done / $total',
            progress: done, max: total, id: _dlNotifId);
      }
    }

    final workers = queue.length < _dlConcurrency ? queue.length : _dlConcurrency;
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);

    _playlistBusy = false;
    _playlistName = null;
    _playlistProgress = 0;
    notifyListeners();
    final body = failed == 0
        ? '$name · $total треков'
        : '$name · скачано ${total - failed}, не удалось $failed';
    await _notif.show('Плейлист скачан', body, id: _dlNotifId);
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
