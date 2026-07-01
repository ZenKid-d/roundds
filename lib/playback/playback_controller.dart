import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models/track.dart';
import 'audio_handler.dart';

/// UI-обёртка над [RoundsAudioHandler]: ChangeNotifier, на который подписан
/// интерфейс. Сам звук и очередь живут в хендлере (audio_service).
class PlaybackController extends ChangeNotifier {
  PlaybackController(this._handler) {
    _handler.onUiChanged = notifyListeners;
    // Позицию НЕ уведомляем на каждый тик (иначе весь плеер перестраивается
    // ~5 раз/сек). Её слушает отдельный positionProvider — обновляется только
    // прогресс-бар. Здесь лишь держим поле актуальным для чтения.
    _subs.add(_handler.player.positionStream.listen((p) => _position = p));
    _subs.add(_handler.player.durationStream.listen((d) {
      if (d != null) _duration = d;
      notifyListeners();
    }));
    _subs.add(_handler.player.playerStateStream.listen((s) {
      _playing = s.playing;
      notifyListeners();
    }));
  }

  final RoundsAudioHandler _handler;
  final List<StreamSubscription<dynamic>> _subs = [];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  List<Track> get queue => _handler.trackQueue;
  Track? get current => _handler.current;
  bool get isPlaying => _playing;
  bool get isLoading => _handler.isLoading;
  String? get error => _handler.error;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isShuffle => _handler.isShuffle;
  LoopMode get repeatMode => _handler.repeatMode;

  void toggleShuffle() => _handler.toggleShuffle();
  void cycleRepeat() => _handler.cycleRepeat();

  double get speed => _handler.speed;
  Future<void> setSpeed(double s) => _handler.setSpeed(s);
  bool get crossfade => _handler.crossfade;
  void setCrossfade(bool on) => _handler.setCrossfade(on);

  Future<void> playTrack(Track track, {List<Track>? queue}) =>
      _handler.playTrack(track, queue: queue);

  Future<void> startRadio(Track seed, List<Track> queue) =>
      _handler.playRadio(seed, queue);
  bool get isRadio => _handler.radioMode;

  Future<void> togglePlay() async {
    if (current == null) return;
    if (_playing) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> pause() => _handler.pause();
  Future<void> next() => _handler.skipToNext();
  Future<void> previous() => _handler.skipToPrevious();
  Future<void> seek(Duration to) => _handler.seek(to);
  void addToQueue(Track t) => _handler.addToQueue(t);
  void reorderQueue(int oldIndex, int newIndex) =>
      _handler.reorderQueue(oldIndex, newIndex);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
