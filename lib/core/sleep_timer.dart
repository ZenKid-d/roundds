import 'dart:async';

import 'package:flutter/foundation.dart';

/// Таймер сна: по истечении вызывает [onElapsed] (обычно — пауза плеера).
class SleepTimerController extends ChangeNotifier {
  Timer? _ticker;
  DateTime? _endsAt;
  VoidCallback? _onElapsed;
  void Function(Duration remaining)? _onTick;

  bool get active => _endsAt != null;

  Duration? get remaining {
    if (_endsAt == null) return null;
    final r = _endsAt!.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  void start(Duration d, VoidCallback onElapsed,
      {void Function(Duration remaining)? onTick}) {
    cancel();
    _onElapsed = onElapsed;
    _onTick = onTick;
    _endsAt = DateTime.now().add(d);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = remaining;
      if (r == null) return;
      if (r <= Duration.zero) {
        final cb = _onElapsed;
        cancel();
        cb?.call();
      } else {
        _onTick?.call(r);
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    _onElapsed = null;
    _onTick = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
