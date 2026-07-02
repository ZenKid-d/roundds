import 'package:flutter/foundation.dart';

import 'update_service.dart';

enum UpdateStage { idle, checking, available, downloading, ready, error }

/// Держит состояние обновления между экранами: найденная версия, прогресс
/// фоновой загрузки и путь к скачанному APK (чтобы установить в любой момент).
class UpdateController extends ChangeNotifier {
  UpdateController(this._svc);
  final UpdateService _svc;

  UpdateStage stage = UpdateStage.idle;
  UpdateInfo? info;
  double progress = 0;
  String? filePath;
  bool _bannerDismissed = false;

  bool get hasUpdate => info != null;
  bool get isDownloading => stage == UpdateStage.downloading;
  bool get isReady => stage == UpdateStage.ready && filePath != null;

  /// Показывать ли плавающий баннер (идёт загрузка или готово к установке).
  bool get bannerVisible =>
      !_bannerDismissed && (isDownloading || isReady);

  /// Проверка новой версии. Возвращает найденное обновление или null.
  Future<UpdateInfo?> check() async {
    // Уже качаем/скачали — не перетираем состояние.
    if (isDownloading || isReady) return info;
    stage = UpdateStage.checking;
    notifyListeners();
    try {
      info = await _svc.check();
      stage = info == null ? UpdateStage.idle : UpdateStage.available;
    } catch (_) {
      stage = UpdateStage.error;
    }
    notifyListeners();
    return info;
  }

  /// Запускает фоновую загрузку APK (не блокирует UI).
  Future<void> download() async {
    final i = info;
    if (i == null || isDownloading || isReady) return;
    stage = UpdateStage.downloading;
    progress = 0;
    _bannerDismissed = false;
    notifyListeners();
    try {
      filePath = await _svc.download(i, onProgress: (p) {
        progress = p;
        notifyListeners();
      });
      stage = UpdateStage.ready;
    } catch (_) {
      stage = UpdateStage.error;
    }
    notifyListeners();
  }

  /// Запускает установщик для скачанного APK.
  Future<void> install() async {
    final p = filePath;
    if (p != null) await _svc.install(p);
  }

  void dismissBanner() {
    _bannerDismissed = true;
    notifyListeners();
  }
}
