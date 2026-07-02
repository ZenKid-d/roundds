import 'package:flutter/services.dart';

/// Мост к нативному Android Visualizer (FFT спектр аудио-сессии ExoPlayer).
class VisualizerChannel {
  VisualizerChannel._();
  static final VisualizerChannel instance = VisualizerChannel._();

  static const _ctrl = MethodChannel('roundds/visualizer_ctrl');
  static const _events = EventChannel('roundds/visualizer');

  Stream<List<double>>? _stream;

  /// Поток полос спектра (0..1). Ленивая широковещательная подписка.
  Stream<List<double>> get bands {
    _stream ??= _events.receiveBroadcastStream().map((e) {
      final list = (e as List).map((x) => (x as num).toDouble()).toList();
      return list;
    });
    return _stream!;
  }

  Future<bool> start(int sessionId) async {
    try {
      final ok =
          await _ctrl.invokeMethod<bool>('start', {'sessionId': sessionId});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _ctrl.invokeMethod('stop');
    } catch (_) {}
  }
}
