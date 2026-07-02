import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Утилиты для экрана «Управление памятью»: размеры и очистка кэша.
class Storage {
  const Storage._();

  /// Суммарный размер файлов в каталоге (рекурсивно), в байтах.
  static Future<int> dirSize(Directory d) async {
    if (!d.existsSync()) return 0;
    var total = 0;
    try {
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// Размер кэша приложения (обложки, временные файлы).
  static Future<int> cacheBytes() async =>
      dirSize(await getTemporaryDirectory());

  /// Очищает кэш изображений (cached_network_image) и оперативный кэш.
  static Future<void> clearCache() async {
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  /// Человекочитаемый размер: Б / КБ / МБ / ГБ.
  static String fmt(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    const units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
    var size = bytes / 1024;
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[i]}';
  }
}
