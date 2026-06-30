import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models/track.dart';
import 'audio_handler.dart';

/// UI-обёртка над [RoundsAudioHandler]: ChangeNotifier, на который подписан
/// интерфейс. Сам звук и очередь живут в хендлере (audio_service).
class PlaybackController extends ChangeNotifier {
  PlaybackController(this._handler) {
    _handler.onUiChanged = notifyListeners;
    _subs.add(_handler.player.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    }));
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

  Future<void> playTrack(Track track, {List<Track>? queue}) =>
      _handler.playTrack(track, queue: queue);

  Future<void> togglePlay() async {
    if (current == null) return;
    if (_playing) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

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
