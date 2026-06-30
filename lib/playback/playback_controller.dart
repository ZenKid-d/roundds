import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/aggregator.dart';
import '../domain/models/track.dart';

/// Единый плеер приложения. Любой трек из любого источника резолвится в URL
/// и проигрывается здесь же (in-app), с фоном и уведомлением через
/// just_audio_background.
class PlaybackController extends ChangeNotifier {
  PlaybackController(this._aggregator) {
    _player.playerStateStream.listen((s) {
      _playing = s.playing;
      if (s.processingState == ProcessingState.completed) {
        next();
      }
      notifyListeners();
    });
    _player.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    });
    _player.durationStream.listen((d) {
      if (d != null) _duration = d;
      notifyListeners();
    });
  }

  final Aggregator _aggregator;
  final AudioPlayer _player = AudioPlayer();

  final List<Track> _queue = [];
  int _index = -1;
  bool _playing = false;
  bool _loading = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  List<Track> get queue => List.unmodifiable(_queue);
  Track? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  bool get isPlaying => _playing;
  bool get isLoading => _loading;
  String? get error => _error;
  Duration get position => _position;
  Duration get duration => _duration;

  /// Запускает [track]; опционально задаёт окружающую очередь.
  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    if (queue != null) {
      _queue
        ..clear()
        ..addAll(queue);
      _index = _queue.indexOf(track);
      if (_index < 0) {
        _queue.insert(0, track);
        _index = 0;
      }
    } else {
      final existing = _queue.indexOf(track);
      if (existing >= 0) {
        _index = existing;
      } else {
        _queue.add(track);
        _index = _queue.length - 1;
      }
    }
    await _load();
  }

  Future<void> _load() async {
    final track = current;
    if (track == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final stream = await _aggregator.resolveStream(track);
      await _player.setAudioSource(
        AudioSource.uri(stream.uri, headers: stream.headers),
      );
      // ВАЖНО: play() завершается только когда трек закончился/поставлен на
      // паузу — НЕ ждём его, иначе флаг загрузки висит весь трек.
      unawaited(_player.play());
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    if (current == null) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> next() async {
    if (_index + 1 < _queue.length) {
      _index++;
      await _load();
    }
  }

  Future<void> previous() async {
    if (_position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (_index > 0) {
      _index--;
      await _load();
    }
  }

  Future<void> seek(Duration to) => _player.seek(to);

  void addToQueue(Track t) {
    _queue.add(t);
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final t = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, t);
    if (_index == oldIndex) {
      _index = newIndex;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
