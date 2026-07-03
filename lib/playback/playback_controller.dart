import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models/track.dart';
import 'audio_handler.dart';

/// UI-обёртка над [RoundsAudioHandler]: ChangeNotifier, на который подписан
/// интерфейс. Сам звук и очередь живут в хендлере (audio_service).
class PlaybackController extends ChangeNotifier {
  PlaybackController(this._handler) {
    _handler.onUiChanged = notifyListeners;
    _handler.onTrackStarted = _onTrackStarted;
    // Позицию НЕ уведомляем на каждый тик (иначе весь плеер перестраивается
    // ~5 раз/сек). Её слушает отдельный positionProvider — обновляется только
    // прогресс-бар. Здесь лишь держим поле актуальным для чтения.
    _subs.add(_handler.player.positionStream.listen((p) {
      _position = p;
      // Периодический сброс наслушанного (чтобы длинные сессии сохранялись).
      if (_playing && _listenSw.elapsedMilliseconds >= 20000) {
        _flushListened();
        _listenSw.start();
      }
    }));
    _subs.add(_handler.player.durationStream.listen((d) {
      if (d != null) _duration = d;
      notifyListeners();
    }));
    _subs.add(_handler.player.playerStateStream.listen((s) {
      _playing = s.playing;
      if (s.playing) {
        if (!_listenSw.isRunning) _listenSw.start();
        _playSince ??= DateTime.now();
      } else {
        _flushListened();
        _accumPlayed();
      }
      notifyListeners();
    }));
  }

  /// Колбэки для Last.fm.
  void Function(Track track)? onNowPlaying;
  void Function(Track track, int startedAtEpochSec)? onScrobble;

  // Учёт проигранного времени текущего трека — для скроббла по правилам Last.fm.
  Track? _npTrack;
  int _npStartedEpoch = 0;
  int _playedMs = 0;
  DateTime? _playSince;

  void _accumPlayed() {
    if (_playSince != null) {
      _playedMs += DateTime.now().difference(_playSince!).inMilliseconds;
      _playSince = null;
    }
  }

  void _onTrackStarted(Track t) {
    _finalizeScrobble();
    _npTrack = t;
    _npStartedEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _playedMs = 0;
    _playSince = _playing ? DateTime.now() : null;
    onNowPlaying?.call(t);
  }

  void _finalizeScrobble() {
    final t = _npTrack;
    if (t == null) return;
    _accumPlayed();
    final dur = t.duration?.inMilliseconds ?? 0;
    if (dur > 0 && dur < 30000) {
      _npTrack = null;
      return; // трек короче 30 сек — не скроббим
    }
    final threshold =
        dur > 0 ? (dur ~/ 2 < 240000 ? dur ~/ 2 : 240000) : 60000;
    if (_playedMs >= threshold && _playedMs >= 20000) {
      onScrobble?.call(t, _npStartedEpoch);
    }
    _npTrack = null;
    _playedMs = 0;
  }

  final RoundsAudioHandler _handler;
  final List<StreamSubscription<dynamic>> _subs = [];
  final Stopwatch _listenSw = Stopwatch();

  /// Колбэк учёта наслушанного времени (в мс). Ставится из провайдера.
  void Function(int ms)? onListened;

  void _flushListened() {
    final ms = _listenSw.elapsedMilliseconds;
    _listenSw
      ..stop()
      ..reset();
    if (ms > 0) onListened?.call(ms);
  }

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
  double get crossfadeSeconds => _handler.crossfadeSeconds;
  void setCrossfadeSeconds(double s) => _handler.setCrossfadeSeconds(s);
  bool get skipSilence => _handler.skipSilence;
  Future<void> setSkipSilence(bool on) => _handler.setSkipSilence(on);
  bool get normalize => _handler.normalize;
  Future<void> setNormalize(bool on) => _handler.setNormalize(on);
  bool get gapless => _handler.gapless;
  Future<void> setGapless(bool on) => _handler.setGapless(on);

  bool get sleepAfterTrack => _handler.sleepAfterTrack;
  void setSleepAfterTrack(bool on) {
    _handler.sleepAfterTrack = on;
    notifyListeners();
  }

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
  Future<void> retry() => _handler.retry();
  Future<void> next() => _handler.skipToNext();
  Future<void> previous() => _handler.skipToPrevious();
  Future<void> seek(Duration to) => _handler.seek(to);
  Future<void> setVolume(double v) => _handler.setVolume(v);
  void addToQueue(Track t) => _handler.addToQueue(t);
  void playNext(Track t) => _handler.playNextInQueue(t);
  void reorderQueue(int oldIndex, int newIndex) =>
      _handler.reorderQueue(oldIndex, newIndex);

  @override
  void dispose() {
    _flushListened();
    _finalizeScrobble();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
