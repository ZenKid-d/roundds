import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final String notes;
  final String apkUrl;
  const UpdateInfo(
      {required this.version, required this.notes, required this.apkUrl});
}

/// Проверка и установка обновлений из публичного релиз-репо (без токенов).
class UpdateService {
  UpdateService(this._dio);
  final Dio _dio;

  static const _repo = 'ZenKid-d/roundds-releases';

  /// Возвращает информацию об обновлении, если доступна новая версия; иначе null.
  Future<UpdateInfo?> check() async {
    final resp = await _dio.get(
      'https://api.github.com/repos/$_repo/releases/latest',
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
    final tag = (resp.data['tag_name'] as String?) ?? '';
    final latest = tag.replaceFirst(RegExp(r'^v'), '').trim();
    final notes = (resp.data['body'] as String?) ?? '';
    final assets = (resp.data['assets'] as List?) ?? [];
    String? apkUrl;
    for (final a in assets) {
      final name = (a as Map)['name'] as String? ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        apkUrl = a['browser_download_url'] as String?;
        break;
      }
    }
    if (apkUrl == null || latest.isEmpty) return null;
    final info = await PackageInfo.fromPlatform();
    if (_isNewer(latest, info.version)) {
      return UpdateInfo(version: latest, notes: notes, apkUrl: apkUrl);
    }
    return null;
  }

  Future<String> currentVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  /// Скачивает APK во временную папку и возвращает путь к файлу.
  Future<String> download(
    UpdateInfo info, {
    void Function(double)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/roundds-update.apk';
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
    await _dio.download(info.apkUrl, path, onReceiveProgress: (r, t) {
      if (t > 0) onProgress?.call(r / t);
    });
    return path;
  }

  /// Запускает системный установщик для ранее скачанного APK.
  Future<void> install(String path) =>
      OpenFilex.open(path, type: 'application/vnd.android.package-archive');

  /// Удаляет все скачанные APK из кэша (вызывается при старте — после установки
  /// обновления приложение перезапускается, и файлы больше не нужны).
  Future<void> cleanupApks() async {
    try {
      final dir = await getTemporaryDirectory();
      if (!dir.existsSync()) return;
      for (final e in dir.listSync()) {
        if (e is File && e.path.toLowerCase().endsWith('.apk')) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  bool _isNewer(String latest, String current) {
    final a = _parts(latest);
    final b = _parts(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  List<int> _parts(String v) {
    final p = v
        .split('.')
        .map((x) => int.tryParse(x.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    while (p.length < 3) {
      p.add(0);
    }
    return p;
  }
}
